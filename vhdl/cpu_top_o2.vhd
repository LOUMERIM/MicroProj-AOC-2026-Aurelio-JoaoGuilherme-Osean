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
--
-- Issue #12 (conflito de dados, RAW): a instrução em ID lê rs e/ou rt que uma
-- instrução em EX (distância 1) ou em MEM (distância 2) ainda vai escrever.
-- Distância 3 (produtora em WB) não é conflito: o banco escreve na 1ª metade
-- do ciclo e lê na 2ª (R2). Escritas em $zero não geram dependência (R1).
-- O aborto ocorre no ciclo da detecção, com a consumidora ainda em ID (antes
-- de qualquer efeito errado): hazard_type = "01", hazard_pc = PC da consumidora.
--
-- Issue #14 (conflito de controle): o beq é resolvido no estágio EX (a ULA faz
-- rs - rt e o sinal zero decide; o somador de alvo também fica em EX). Um beq
-- tomado em EX tem sempre instruções já buscadas depois dele (em ID e IF), que
-- seriam executadas indevidamente, porque a O2 não faz flush: o processador
-- aborta com hazard_type = "11" e hazard_pc = PC do desvio. Buscar em
-- sequência após um beq não tomado é o caminho correto, então não é conflito.
-- Justificativa da escolha de EX: docs/controle-o2.md.
--
-- Prioridade quando mais de um conflito ocorre no mesmo ciclo: vale o da
-- instrução mais antiga — controle (EX), depois dados (ID), depois estrutural
-- (IF). As instruções mais novas são descartadas pelo aborto de qualquer forma.
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
    -- Snapshot do slot IF no instante do aborto: mantém stage_valid(0) com o
    -- estado congelado da detecção (issue #15).
    signal if_slot_frozen : std_logic := '0';
    signal if_slot_now    : std_logic;

    -- Detecção do conflito estrutural (issue #13).
    signal structural_conflict : std_logic;

    -- Detecção do conflito de dados (issue #12).
    signal data_conflict  : std_logic;
    signal id_uses_rs     : std_logic;          -- instrução em ID lê rs
    signal id_uses_rt     : std_logic;          -- instrução em ID lê rt
    signal branch_taken   : std_logic;          -- beq tomado em EX neste ciclo

    -- Detecção do conflito de controle (issue #14).
    signal control_conflict : std_logic;
    signal branch_pc        : word_t;           -- PC do beq em EX

    -- Tipo e PC do conflito, registrados no ciclo do aborto (estáveis até o reset).
    signal hazard_type_reg : std_logic_vector(1 downto 0) := "00";
    signal hazard_pc_reg   : word_t := (others => '0');

    -- Contagem de ciclos na convenção do tb_cpu (1-based): o tb incrementa o
    -- contador na borda de descida de cada ciclo; aqui contamos na borda de
    -- subida do mesmo ciclo. O reset zera a contagem para que hazard_cycle
    -- recomece em 1 após um aborto (issue #15).
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
    -- borda de descida do ciclo de WB (escreve na 1ª metade, lê na 2ª: a distância 3 já enxerga o valor novo).
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
    -- (Somador de alvo do caminho de dados em EX. Na O2 sem flush o PC nunca é
    -- redirecionado: todo beq tomado aborta por conflito de controle, issue #14.)
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

    ----------------------------------------------------------------------------
    -- Detecção do conflito de dados (issue #12).
    ----------------------------------------------------------------------------
    -- Quais registradores a instrução em ID realmente lê:
    --   rs: tipo R (exceto break), addi, lw, sw, beq
    --   rt: tipo R (exceto break), sw (dado a gravar), beq
    -- Em addi/lw o campo rt é o destino, então não gera dependência.
    operand_use : process (all)
        variable opcode : std_logic_vector(5 downto 0);
    begin
        opcode := ifid_reg.instr(31 downto 26);
        id_uses_rs <= '0';
        id_uses_rt <= '0';
        if ifid_reg.valid = '1' then
            case opcode is
                when OP_R =>
                    if not is_break_instr(ifid_reg.instr) then
                        id_uses_rs <= '1';
                        id_uses_rt <= '1';
                    end if;
                when OP_ADDI | OP_LW =>
                    id_uses_rs <= '1';
                when OP_SW | OP_BEQ =>
                    id_uses_rs <= '1';
                    id_uses_rt <= '1';
                when others =>
                    null;
            end case;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Detecção do conflito de controle (issue #14): beq resolvido em EX.
    ----------------------------------------------------------------------------
    -- O desvio é tomado quando rs - rt = 0 (alu_zero) para um beq válido em EX.
    branch_taken <= idex_reg.valid and idex_reg.is_beq and alu_zero;
    -- ID/EX guarda PC+4; o PC do próprio beq é PC+4 - 4.
    branch_pc    <= std_logic_vector(unsigned(idex_reg.pc_plus4) - 4);

    -- Conflito: desvio tomado com instrução já buscada depois dele (em ID ou
    -- IF). beq não tomado nunca gera conflito.
    control_conflict <= '1' when branch_taken = '1'
                             and (ifid_reg.valid = '1' or fetch_valid_now = '1')
                             and frozen = '0'
                        else '0';

    -- Um beq tomado em EX tem prioridade (é mais antigo): a instrução em ID é do
    -- caminho errado e não é tratada como consumidora de conflito de dados.

    data_detect : process (all)
        variable rs, rt : reg_addr_t;
        variable hit    : boolean;
    begin
        rs  := ifid_reg.instr(25 downto 21);
        rt  := ifid_reg.instr(20 downto 16);
        hit := false;

        -- Distância 1: produtora em EX (ID/EX).
        if idex_reg.valid = '1' and idex_reg.wb_enable = '1'
           and idex_reg.wb_addr /= "00000" then
            if (id_uses_rs = '1' and rs = idex_reg.wb_addr) or
               (id_uses_rt = '1' and rt = idex_reg.wb_addr) then
                hit := true;
            end if;
        end if;

        -- Distância 2: produtora em MEM (EX/MEM).
        if exmem_reg.valid = '1' and exmem_reg.wb_enable = '1'
           and exmem_reg.wb_addr /= "00000" then
            if (id_uses_rs = '1' and rs = exmem_reg.wb_addr) or
               (id_uses_rt = '1' and rt = exmem_reg.wb_addr) then
                hit := true;
            end if;
        end if;

        -- Distância 3 (produtora em WB) não entra: escrita na 1ª metade do ciclo.
        if hit and frozen = '0' and branch_taken = '0' then
            data_conflict <= '1';
        else
            data_conflict <= '0';
        end if;
    end process;

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
                if_slot_frozen <= '0';
                hazard_type_reg <= "00";
                hazard_pc_reg   <= (others => '0');
            elsif control_conflict = '1' then
                -- Issue #14: aborta no ciclo em que o beq tomado está em EX. As
                -- instruções do caminho errado (ID e IF) não avançam e nunca
                -- produzem efeito; as mais antigas, em MEM e WB, concluem o que
                -- já tinham iniciado, como nos demais conflitos (issue #15).
                frozen          <= '1';
                if_slot_frozen  <= fetch_valid_now;
                hazard_type_reg <= "11";
                hazard_pc_reg   <= branch_pc;
            elsif data_conflict = '1' then
                -- Issue #12/#15: aborta com a consumidora ainda em ID. Nada
                -- avança nesta borda (PC e registradores entre estágios ficam
                -- como no ciclo da detecção); as instruções mais antigas, em
                -- MEM e WB, concluem o que já tinham iniciado, como no conflito
                -- estrutural. Tipo e PC ficam registrados até o reset.
                frozen          <= '1';
                if_slot_frozen  <= fetch_valid_now;
                hazard_type_reg <= "01";
                hazard_pc_reg   <= ifid_reg.pc;
            elsif structural_conflict = '1' then
                -- Issue #13/#15: ciclo da detecção do conflito estrutural. A
                -- instrução mais antiga (MEM) conclui o acesso concedido — a
                -- escrita acontece nesta borda, dentro da memória. A mais
                -- nova (IF) é abortada: nada avança. O congelamento é
                -- registrado aqui e todo o estado fica estável até o reset.
                frozen        <= '1';
                if_slot_frozen <= fetch_valid_now;
                hazard_type_reg <= "10";
                hazard_pc_reg   <= pc;   -- PC da instrução em IF (a mais nova)
            elsif frozen = '1' then
                -- Aborto (R4): congelar PC, pipeline, banco e memória; os
                -- sinais hazard_* permanecem estáveis até o reset.
                null;
            else
                -- PC: avança uma palavra por ciclo. Sem flush, um beq tomado
                -- nunca chega a redirecionar o PC: ele aborta antes (issue #14).
                pc <= std_logic_vector(unsigned(pc) + 4);

                -- IF/ID: bolha depois de um break no ID.
                ifid_reg.valid <= fetch_valid_now;
                if fetch_valid_now = '1' then
                    ifid_reg.pc    <= pc;
                    ifid_reg.instr <= if_instr;
                end if;

                -- O fluxo de instruções termina quando um break chega ao ID.
                if ifid_reg.valid = '1' and is_break_instr(ifid_reg.instr) then
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

            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Interface R3.
    ----------------------------------------------------------------------------
    -- Semântica de aborto (issue #15): hazard_abort/hazard_type são
    -- combinacionais com o ciclo da detecção e ficam estáveis depois, porque
    -- o congelamento impede que um novo conflito seja detectado (todos os
    -- detectores exigem frozen = '0'). O primeiro hazard detectado, portanto,
    -- é o único reportado. Conflitos simultâneos: controle > dados > estrutural.
    done <= done_reg or (memwb_reg.valid and memwb_reg.is_break);

    -- No ciclo da detecção os valores saem da lógica de detecção; depois do
    -- congelamento, dos registradores (estáveis até o reset).
    hazard_abort <= frozen or control_conflict or data_conflict or structural_conflict;
    hazard_type  <= hazard_type_reg when frozen = '1' else
                    "11"            when control_conflict = '1' else
                    "01"            when data_conflict = '1' else
                    "10"            when structural_conflict = '1' else
                    "00";
    -- Controle: PC do desvio (EX). Dados: PC da consumidora (ID). Estrutural:
    -- PC da instrução em IF, a mais nova, que não obteve o recurso.
    hazard_pc    <= hazard_pc_reg   when frozen = '1' else
                    branch_pc       when control_conflict = '1' else
                    ifid_reg.pc     when data_conflict = '1' else
                    pc;
    hazard_cycle <= cycle_cnt + 1 when frozen = '0' else cycle_cnt;

    retired <= "01" when (memwb_reg.valid = '1'
                          and memwb_reg.is_break = '0'
                          and frozen = '0')
               else "00";

    -- Slots 0..4: IF, ID (IF/ID), EX (ID/EX), MEM (EX/MEM), WB (MEM/WB).
    -- Após o aborto, o slot IF mostra o valor congelado no instante da
    -- detecção (snapshot), não a busca corrente (issue #15).
    if_slot_now <= fetch_valid_now when frozen = '0' else if_slot_frozen;

    stage_valid <= (0 => if_slot_now,
                    1 => ifid_reg.valid,
                    2 => idex_reg.valid,
                    3 => exmem_reg.valid,
                    4 => memwb_reg.valid,
                    others => '0');

    -- Contagem de ciclos na convenção do tb_cpu (ver cycle_cnt acima).
    cycle_counter : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cycle_cnt <= (others => '0');
            elsif frozen = '0' then
                cycle_cnt <= cycle_cnt + 1;
            end if;
        end if;
    end process;
end architecture;
