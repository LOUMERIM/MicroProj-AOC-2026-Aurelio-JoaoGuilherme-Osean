library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.o1_pkg.all;
use work.o2_pkg.all;

-- O2: pipeline de 5 estágios (IF, ID, EX, MEM, WB), em ordem, sem forwarding
-- nem stall. Conflitos são detectados e abortam a simulação (R4, issue #15).
--
-- Issue #13 (conflito estrutural): com MEM_UNIFICADA = true, IF busca uma
-- instrução na memória unificada enquanto um lw/sw válido ocupa a porta de
-- dados no estágio MEM no mesmo ciclo. A instrução mais antiga (MEM) mantém
-- o recurso; a mais nova (IF) não o obteve e é apontada por hazard_pc.
-- hazard_type = "10" e hazard_pc/hazard_cycle ficam estáveis até o reset.
entity cpu_top_o2 is
    generic (
        PROG_FILE     : string  := "tracos/t0.hex";
        MEM_UNIFICADA : boolean := false
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        done         : out std_logic;
        hazard_abort : out std_logic;
        hazard_type  : out std_logic_vector(1 downto 0);
        hazard_pc    : out std_logic_vector(31 downto 0);
        hazard_cycle : out unsigned(31 downto 0);
        retired      : out unsigned(1 downto 0);
        stage_valid  : out std_logic_vector(9 downto 0);
        dbg_reg_addr : in  std_logic_vector(4 downto 0);
        dbg_reg_data : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of cpu_top_o2 is
    signal pc : word_t := (others => '0');

    -- Registradores entre estágios (com bit de validade).
    signal ifid_reg   : ifid_t;
    signal idex_reg   : idex_t;
    signal exmem_reg  : exmem_t;
    signal memwb_reg  : memwb_t;
    -- Próximos valores combinacionais dos registradores.
    signal idex_next  : idex_t;

    -- Controle de fluxo.
    signal frozen         : std_logic := '0';   -- semântica de aborto (R4)
    signal done_reg       : std_logic := '0';
    signal stream_active  : std_logic := '1';   -- fluxo de instruções não chegou ao fim
    signal fetch_valid_now : std_logic;         -- instrução real (não bolha) em IF

    -- Detecção do conflito estrutural (issue #13).
    signal structural_conflict : std_logic;

    -- Contagem de ciclos na convenção do tb_cpu (1-based): o tb incrementa o
    -- contador na borda de descida de cada ciclo; aqui contamos na borda de
    -- subida do mesmo ciclo.
    signal cycle_cnt : unsigned(31 downto 0) := (others => '0');

    -- Caminho de dados.
    signal if_instr        : word_t;
    signal mem_read_data   : word_t;
    signal register_read_a : word_t;
    signal register_read_b : word_t;
    signal alu_operand_a   : word_t;
    signal alu_operand_b   : word_t;
    signal alu_result      : word_t;
    signal alu_zero        : std_logic;
    signal branch_target   : word_t;
    signal mem_read_en     : std_logic;
    signal mem_write_en    : std_logic;
    signal wb_write_en     : std_logic;
begin
    ----------------------------------------------------------------------------
    -- Memórias: separadas (padrão) ou unificada (MEM_UNIFICADA = true).
    ----------------------------------------------------------------------------
    gen_mem_separada : if not MEM_UNIFICADA generate
    begin
        instruction_store : entity work.instruction_memory
            generic map (
                DEPTH     => 4096,
                INIT_FILE => PROG_FILE
            )
            port map (
                address => pc,
                data    => if_instr
            );

        data_store : entity work.data_memory
            generic map (
                DEPTH => 256
            )
            port map (
                clk          => clk,
                address      => exmem_reg.alu_result,
                read_enable  => mem_read_en,
                write_enable => mem_write_en,
                write_data   => exmem_reg.store_data,
                read_data    => mem_read_data
            );
    end generate gen_mem_separada;

    gen_mem_unificada : if MEM_UNIFICADA generate
    begin
        unified_store : entity work.unified_memory
            generic map (
                DEPTH     => 4096,
                INIT_FILE => PROG_FILE
            )
            port map (
                clk              => clk,
                if_address       => pc,
                if_data          => if_instr,
                mem_address      => exmem_reg.alu_result,
                mem_read_enable  => mem_read_en,
                mem_read_data    => mem_read_data,
                mem_write_enable => mem_write_en,
                mem_write_data   => exmem_reg.store_data
            );
    end generate gen_mem_unificada;

    ----------------------------------------------------------------------------
    -- Banco de registradores: leituras assíncronas no estágio ID, escrita na
    -- borda de descida do ciclo de WB (distância >= 4 dispensa forwarding).
    ----------------------------------------------------------------------------
    registers : entity work.register_file
        port map (
            clk          => clk,
            rst          => rst,
            write_enable => wb_write_en,
            write_addr   => memwb_reg.wb_addr,
            write_data   => memwb_reg.wb_data,
            read_addr_1  => ifid_reg.instr(25 downto 21),
            read_data_1  => register_read_a,
            read_addr_2  => ifid_reg.instr(20 downto 16),
            read_data_2  => register_read_b,
            dbg_reg_addr => dbg_reg_addr,
            dbg_reg_data => dbg_reg_data
        );

    wb_write_en <= memwb_reg.valid and memwb_reg.wb_enable and (not frozen);

    ----------------------------------------------------------------------------
    -- ALU do estágio EX + somador de desvio.
    ----------------------------------------------------------------------------
    alu_operand_a <= idex_reg.rs_value;
    alu_operand_b <= idex_reg.rt_value when idex_reg.use_imm = '0' else idex_reg.imm;

    arithmetic_logic_unit : entity work.alu
        port map (
            operand_a => alu_operand_a,
            operand_b => alu_operand_b,
            operation => idex_reg.alu_op,
            result    => alu_result,
            zero      => alu_zero
        );

    -- beq tomado: alvo = PC+4 + (imediato << 2).
    branch_target <= std_logic_vector(unsigned(idex_reg.pc_plus4) +
                                       shift_left(unsigned(idex_reg.imm), 2));

    ----------------------------------------------------------------------------
    -- Estágio ID: decodifica a instrução em IF/ID.
    ----------------------------------------------------------------------------
    decode : process (all)
        variable opcode : std_logic_vector(5 downto 0);
        variable funct  : std_logic_vector(5 downto 0);
    begin
        idex_next <= (
            valid     => '0',
            pc_plus4  => (others => '0'),
            rs_value  => (others => '0'),
            rt_value  => (others => '0'),
            imm       => (others => '0'),
            alu_op    => ALU_ADD,
            use_imm   => '0',
            is_lw     => '0',
            is_sw     => '0',
            is_beq    => '0',
            is_break  => '0',
            wb_enable => '0',
            wb_addr   => (others => '0')
        );

        if ifid_reg.valid = '1' then
            opcode := ifid_reg.instr(31 downto 26);
            funct  := ifid_reg.instr(5 downto 0);

            idex_next.valid    <= '1';
            idex_next.pc_plus4 <= std_logic_vector(unsigned(ifid_reg.pc) + 4);
            idex_next.rs_value <= register_read_a;
            idex_next.rt_value <= register_read_b;
            idex_next.imm      <= std_logic_vector(resize(signed(ifid_reg.instr(15 downto 0)), 32));
            idex_next.wb_addr  <= ifid_reg.instr(20 downto 16);  -- formato I

            case opcode is
                when OP_R =>
                    idex_next.use_imm   <= '0';
                    idex_next.wb_enable <= '1';
                    idex_next.wb_addr   <= ifid_reg.instr(15 downto 11);  -- formato R
                    if is_break_instr(ifid_reg.instr) then
                        idex_next.is_break <= '1';
                    elsif funct = "100000" then
                        idex_next.alu_op <= ALU_ADD;
                    elsif funct = "100010" then
                        idex_next.alu_op <= ALU_SUB;
                    elsif funct = "100100" then
                        idex_next.alu_op <= ALU_AND;
                    elsif funct = "100101" then
                        idex_next.alu_op <= ALU_OR;
                    elsif funct = "101010" then
                        idex_next.alu_op <= ALU_SLT;
                    else
                        assert false
                            report "Unsupported R-format function code"
                            severity failure;
                    end if;

                when OP_ADDI =>
                    idex_next.use_imm   <= '1';
                    idex_next.wb_enable <= '1';

                when OP_LW =>
                    idex_next.use_imm   <= '1';
                    idex_next.is_lw     <= '1';
                    idex_next.wb_enable <= '1';

                when OP_SW =>
                    idex_next.use_imm <= '1';
                    idex_next.is_sw   <= '1';

                when OP_BEQ =>
                    idex_next.is_beq <= '1';
                    idex_next.alu_op <= ALU_SUB;

                when others =>
                    assert false
                        report "Unsupported instruction opcode"
                        severity failure;
            end case;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Detecção do conflito estrutural (issue #13): apenas com memória
    -- unificada, instrução real em IF e lw/sw válida em MEM no mesmo ciclo.
    ----------------------------------------------------------------------------
    structural_conflict <= '1' when MEM_UNIFICADA
                             and fetch_valid_now = '1'
                             and exmem_reg.valid = '1'
                             and (exmem_reg.is_lw = '1' or exmem_reg.is_sw = '1')
                         else '0';

    -- A instrução em IF é real enquanto o fluxo de instruções não terminou.
    -- A entrada em IF também é suprimida no ciclo em que um break está no ID
    -- (a instrução seguinte vira bolha).
    fetch_valid_now <= '1' when stream_active = '1'
                           and frozen = '0'
                           and not (ifid_reg.valid = '1'
                                    and is_break_instr(ifid_reg.instr))
                   else '0';

    -- Acesso à porta de dados no estágio MEM, suspenso quando congelado.
    mem_read_en  <= exmem_reg.valid and exmem_reg.is_lw and (not frozen);
    mem_write_en <= exmem_reg.valid and exmem_reg.is_sw and (not frozen);

    ----------------------------------------------------------------------------
    -- Registradores entre estágios e semântica de aborto (issues #11 e #15).
    ----------------------------------------------------------------------------
    pipeline_reg : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc            <= (others => '0');
                ifid_reg      <= (valid => '0', pc => (others => '0'), instr => (others => '0'));
                idex_reg      <= (valid => '0', pc_plus4 => (others => '0'),
                                  rs_value => (others => '0'), rt_value => (others => '0'),
                                  imm => (others => '0'), alu_op => ALU_ADD, use_imm => '0',
                                  is_lw => '0', is_sw => '0', is_beq => '0', is_break => '0',
                                  wb_enable => '0', wb_addr => (others => '0'));
                exmem_reg     <= (valid => '0', alu_result => (others => '0'),
                                  store_data => (others => '0'), is_lw => '0', is_sw => '0',
                                  is_break => '0', wb_enable => '0', wb_addr => (others => '0'));
                memwb_reg     <= (valid => '0', wb_enable => '0', wb_addr => (others => '0'),
                                  wb_data => (others => '0'), is_break => '0');
                frozen        <= '0';
                done_reg      <= '0';
                stream_active <= '1';
            elsif frozen = '1' then
                -- Aborto (R4): congelar PC, pipeline, banco e memória; os
                -- sinais hazard_* permanecem estáveis até o reset.
                null;
            else
                -- PC: avança uma palavra por ciclo (desvio tomado sobrepõe).
                if idex_reg.valid = '1' and idex_reg.is_beq = '1' and alu_zero = '1' then
                    pc <= branch_target;
                else
                    pc <= std_logic_vector(unsigned(pc) + 4);
                end if;

                -- IF/ID: bolha depois de um break no ID ou em desvio tomado.
                ifid_reg.valid <= fetch_valid_now;
                if fetch_valid_now = '1' then
                    ifid_reg.pc    <= pc;
                    ifid_reg.instr <= if_instr;
                end if;

                -- O fluxo de instruções termina quando um break commita no
                -- pipeline (chegou ao ID sem ser morto por um flush de
                -- desvio tomado no mesmo ciclo).
                if ifid_reg.valid = '1'
                   and is_break_instr(ifid_reg.instr)
                   and not (idex_reg.valid = '1'
                            and idex_reg.is_beq = '1' and alu_zero = '1') then
                    stream_active <= '0';
                end if;

                -- ID/EX
                idex_reg <= idex_next;

                -- EX/MEM
                exmem_reg.valid      <= idex_reg.valid;
                exmem_reg.alu_result <= alu_result;
                exmem_reg.store_data <= idex_reg.rt_value;
                exmem_reg.is_lw      <= idex_reg.is_lw;
                exmem_reg.is_sw      <= idex_reg.is_sw;
                exmem_reg.is_break   <= idex_reg.is_break;
                exmem_reg.wb_enable  <= idex_reg.wb_enable;
                exmem_reg.wb_addr    <= idex_reg.wb_addr;

                -- MEM/WB (lw escolhe o dado da memória; demais usam a ALU)
                memwb_reg.valid     <= exmem_reg.valid;
                memwb_reg.wb_enable <= exmem_reg.wb_enable;
                memwb_reg.wb_addr   <= exmem_reg.wb_addr;
                memwb_reg.is_break  <= exmem_reg.is_break;
                if exmem_reg.is_lw = '1' then
                    memwb_reg.wb_data <= mem_read_data;
                else
                    memwb_reg.wb_data <= exmem_reg.alu_result;
                end if;

                -- done quando o break conclui o WB (as instruções mais antigas
                -- já concluíram; o break não entra na contagem de retired).
                if memwb_reg.valid = '1' and memwb_reg.is_break = '1' then
                    done_reg <= '1';
                end if;

                -- Issue #13: a instrução mais antiga (MEM) mantém o recurso e
                -- conclui o acesso; a mais nova (IF) é abortada no fim do ciclo.
                if structural_conflict = '1' then
                    frozen <= '1';
                end if;

                -- Desvio tomado: mata a busca corrente e a instrução em ID.
                if idex_reg.valid = '1' and idex_reg.is_beq = '1' and alu_zero = '1' then
                    pc             <= branch_target;
                    ifid_reg.valid <= '0';
                    idex_reg.valid <= '0';
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Interface R3.
    ----------------------------------------------------------------------------
    done <= done_reg or (memwb_reg.valid and memwb_reg.is_break);

    hazard_abort <= frozen or structural_conflict;
    hazard_type  <= "10" when (frozen = '1' or structural_conflict = '1') else "00";
    -- Durante o conflito, o PC da instrução em IF (a mais nova, que não obteve
    -- o recurso); após o congelamento, o PC permanece nesse valor.
    hazard_pc    <= pc;
    hazard_cycle <= cycle_cnt + 1 when frozen = '0' else cycle_cnt;

    retired <= "01" when (memwb_reg.valid = '1'
                          and memwb_reg.is_break = '0'
                          and frozen = '0')
               else "00";

    -- Slots 0..4: IF, ID (IF/ID), EX (ID/EX), MEM (EX/MEM), WB (MEM/WB).
    stage_valid <= (0 => fetch_valid_now,
                    1 => ifid_reg.valid,
                    2 => idex_reg.valid,
                    3 => exmem_reg.valid,
                    4 => memwb_reg.valid,
                    others => '0');

    -- Contagem de ciclos na convenção do tb_cpu (ver cycle_cnt acima).
    cycle_counter : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '0' and frozen = '0' then
                cycle_cnt <= cycle_cnt + 1;
            end if;
        end if;
    end process;
end architecture;
