library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_cpu is
    generic (
        PROG_FILE      : string := "tracos/t0.hex"; -- programa (.hex)
        ESPERADO_FILE  : string := "tracos/t0_esperado.txt"; -- linhas "reg valor_hex"
        ORG_NOME       : string := "O2"; -- rótulo usado na saída
        NUM_SLOTS      : positive := 5; -- O1 = 1, O2 = 5
        MEM_UNIFICADA  : boolean := false; -- true só no traço TE de O2
        ESPERA_ABORTO  : boolean := false; -- true nos traços TD, TE e TC
        TIPO_ESPERADO  : natural := 0; -- 1 dados, 2 estrutural, 3 controle
        PC_ESPERADO    : std_logic_vector(31 downto 0) := (others => '0'); -- PC esperado para conflitos
        T_CLK          : time := 10 ns; -- período de SIMULAÇÃO, não o real
        MAX_CICLOS     : natural := 10_000 -- proteção contra laço infinito
    );
end entity;

architecture sim of tb_cpu is
    constant PC_ZERO : std_logic_vector(31 downto 0) := (others => '0');
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal fim_sim        : boolean := false;
    signal done           : std_logic;
    signal hazard_abort   : std_logic;
    signal hazard_type    : std_logic_vector(1 downto 0);
    signal hazard_pc      : std_logic_vector(31 downto 0);
    signal hazard_cycle   : unsigned(31 downto 0);
    signal retired        : unsigned(1 downto 0);
    signal stage_valid    : std_logic_vector(9 downto 0);
    signal dbg_reg_addr   : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_reg_data    : std_logic_vector(31 downto 0);

begin
    -- 1. Geração de clock
    clk <= not clk after T_CLK / 2 when not fim_sim else '0';

    -- 2. DUT
    -- O rótulo ORG_NOME (preenchido pela variável ORG do make) também seleciona
    -- o núcleo: "O2" instancia o pipeline; qualquer outro valor usa a O1.
    gen_o1 : if ORG_NOME /= "O2" generate
    begin
        dut : entity work.cpu_top
            generic map (
                PROG_FILE     => PROG_FILE,
                MEM_UNIFICADA => MEM_UNIFICADA
            )
            port map (
                clk           => clk,
                rst           => rst,
                done          => done,
                hazard_abort  => hazard_abort,
                hazard_type   => hazard_type,
                hazard_pc     => hazard_pc,
                hazard_cycle  => hazard_cycle,
                retired       => retired,
                stage_valid   => stage_valid,
                dbg_reg_addr  => dbg_reg_addr,
                dbg_reg_data  => dbg_reg_data
            );
    end generate gen_o1;

    gen_o2 : if ORG_NOME = "O2" generate
    begin
        dut : entity work.cpu_top_o2
            generic map (
                PROG_FILE     => PROG_FILE,
                MEM_UNIFICADA => MEM_UNIFICADA
            )
            port map (
                clk           => clk,
                rst           => rst,
                done          => done,
                hazard_abort  => hazard_abort,
                hazard_type   => hazard_type,
                hazard_pc     => hazard_pc,
                hazard_cycle  => hazard_cycle,
                retired       => retired,
                stage_valid   => stage_valid,
                dbg_reg_addr  => dbg_reg_addr,
                dbg_reg_data  => dbg_reg_data
            );
    end generate gen_o2;

    -- 3. Processo principal
    principal : process
        type contagem_t is array (0 to 9) of natural;
        -- números do CSV em formato fixo, 6 casas decimais
        impure function fmt(x : real) return string is
        begin
            return to_string(x, 6);
        end function;
        file f_esp : text;
        file f_csv : text;
        variable l : line;
        variable st : file_open_status;
        variable ciclos : natural := 0;
        variable instrs : natural := 0;
        variable ocupados : natural := 0;
        variable ocup_slot : contagem_t := (others => 0);  -- ciclos com stage_valid(i) = 1
        variable slots_via0, slots_via1 : natural;
        variable soma : natural;
        variable existe_csv : boolean;
        variable desfecho : line;
        variable erros : natural := 0;
        variable reg_num : integer;
        variable valor : std_logic_vector(31 downto 0);
        variable cpi, ipc, ocup : real := 0.0;
        -- cópias no instante do aborto, para checar estabilidade (issue #15)
        variable v_abort : std_logic;
        variable v_type  : std_logic_vector(1 downto 0);
        variable v_pc    : std_logic_vector(31 downto 0);
        variable v_cycle : unsigned(31 downto 0);
        variable v_stage : std_logic_vector(9 downto 0);
    begin
        -- 3.1 Reset
        rst <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';

        -- 3.2 Execução
        loop
            wait until falling_edge(clk);
            ciclos := ciclos + 1;
            instrs := instrs + to_integer(retired);
            for i in 0 to NUM_SLOTS - 1 loop
                if stage_valid(i) = '1' then
                    ocupados := ocupados + 1;
                    ocup_slot(i) := ocup_slot(i) + 1;
                end if;
            end loop;
            exit when done = '1' or hazard_abort = '1' or ciclos = MAX_CICLOS;
        end loop;

        -- Desfecho registrado aqui: a verificação da semântica de aborto (3.3.2)
        -- reseta o DUT depois, e hazard_abort volta a 0 antes das métricas.
        if done = '1' then
            write(desfecho, string'("done"));
        elsif hazard_abort = '1' then
            write(desfecho, string'("aborto"));
        else
            write(desfecho, string'("tempo_esgotado"));
        end if;

        -- 3.3 Desfecho
        if hazard_abort = '1' then
            report ORG_NOME & ": ABORTO tipo=" & to_string(hazard_type) &
                   " pc=0x" & to_hstring(hazard_pc) &
                   " ciclo=" & integer'image(to_integer(hazard_cycle));
            
            assert ESPERA_ABORTO
                report "Aborto inesperado: o traço deveria ser livre de conflitos"
                severity error;
            
            assert to_integer(unsigned(hazard_type)) = TIPO_ESPERADO
                report "Tipo de conflito diferente do esperado"
                severity error;
            
            -- Divergência em hazard_pc falha o teste quando um PC esperado é
            -- configurado (PC_ESPERADO /= 0); sem expectativa, não há o que
            -- conferir (issue #15).
            if PC_ESPERADO /= PC_ZERO then
                assert hazard_pc = PC_ESPERADO
                    report "hazard_pc difere do esperado"
                    severity error;
            end if;

            assert to_integer(hazard_cycle) = ciclos
                report "hazard_cycle difere da contagem do testbench"
                severity error;

            -- 3.3.1 Semântica de aborto (R4, issue #15): o estado congelado
            -- mantém os sinais hazard_* estáveis por vários ciclos, nada é
            -- aposentado e os slots válidos não mudam.
            v_abort := hazard_abort;
            v_type  := hazard_type;
            v_pc    := hazard_pc;
            v_cycle := hazard_cycle;
            v_stage := stage_valid;
            for i in 1 to 5 loop
                wait until falling_edge(clk);

                assert hazard_abort = v_abort
                    report "hazard_abort não permaneceu estável após o aborto"
                    severity error;
                assert hazard_type = v_type
                    report "hazard_type não permaneceu estável após o aborto"
                    severity error;
                assert hazard_pc = v_pc
                    report "hazard_pc não permaneceu estável após o aborto"
                    severity error;
                assert hazard_cycle = v_cycle
                    report "hazard_cycle não permaneceu estável após o aborto"
                    severity error;
                assert stage_valid = v_stage
                    report "stage_valid não permaneceu estável após o aborto"
                    severity error;
                assert to_integer(retired) = 0
                    report "instrução foi aposentada após o congelamento"
                    severity error;
            end loop;

            -- 3.3.2 O reset limpa o estado de aborto e os metadados: sem
            -- hazard, e a contagem de ciclos recomeça em 1 (issue #15).
            rst <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            rst <= '0';
            wait until falling_edge(clk);

            assert hazard_abort = '0'
                report "reset não limpou hazard_abort"
                severity error;
            assert hazard_type = "00"
                report "reset não limpou hazard_type"
                severity error;
            assert to_integer(hazard_cycle) = 1
                report "hazard_cycle não reiniciou em 1 após o reset"
                severity error;
            assert to_integer(retired) = 0
                report "reset não limpou retired"
                severity error;

        elsif done = '1' then
            assert not ESPERA_ABORTO
                report "Conflito esperado não foi detectado"
                severity error;

            -- 3.4 Verificação automática
            file_open(st, f_esp, ESPERADO_FILE, read_mode);
            assert st = open_ok
                report "Não foi possível abrir " & ESPERADO_FILE severity failure;
            
            while not endfile(f_esp) loop
                readline(f_esp, l);
                next when l'length = 0;
                next when l(1) = '#';
                
                read(l, reg_num);
                hread(l, valor);
                
                dbg_reg_addr <= std_logic_vector(to_unsigned(reg_num, 5));
                wait for 1 ns;
                
                if dbg_reg_data /= valor then
                    erros := erros + 1;
                    report "Reg " & integer'image(reg_num) & ": esperado 0x" & 
                           to_hstring(valor) & ", obtido 0x" & to_hstring(dbg_reg_data)
                           severity error;
                end if;
            end loop;
            file_close(f_esp);

        else
            report ORG_NOME & ": tempo esgotado em " & integer'image(ciclos) & " ciclos" severity failure;
        end if;

        -- 3.5 Métricas (R6)
        -- ciclos: do 1º ciclo após o reset até o ciclo em que done = 1, inclusive
        --         (o laço de 3.2 conta o ciclo antes de testar done).
        -- instrs: soma de retired; o break não é instrução útil e o DUT não o
        --         conta em retired (O1 e O2), então não entra no CPI/IPC.
        if instrs > 0 then
            cpi := real(ciclos) / real(instrs);
            ipc := real(instrs) / real(ciclos);
        end if;
        ocup := real(ocupados) / real(ciclos * NUM_SLOTS);

        -- Cabeçalho só quando o arquivo ainda não existe (ou está vazio).
        file_open(st, f_csv, "metricas.csv", read_mode);
        existe_csv := st = open_ok;
        if existe_csv then
            existe_csv := not endfile(f_csv);
            file_close(f_csv);
        end if;

        file_open(st, f_csv, "metricas.csv", append_mode);
        if not existe_csv then
            write(l, string'("org;programa;ciclos;instrucoes;CPI;IPC;ocupacao;erros;desfecho;" &
                             "ocup_IF;ocup_ID;ocup_EX;ocup_MEM;ocup_WB;ocup_via0;ocup_via1"));
            writeline(f_csv, l);
        end if;
        -- Colunas do modelo do enunciado (3.5), na mesma ordem...
        write(l, ORG_NOME & ";" & PROG_FILE & ";" & integer'image(ciclos) & ";" &
               integer'image(instrs) & ";" & fmt(cpi) & ";" &
               fmt(ipc) & ";" & fmt(ocup) & ";" &
               integer'image(erros) & ";" & desfecho.all);
        -- ...e ocupação por estágio da via 0 (bits 0..4 = IF, ID, EX, MEM, WB) e
        -- por via. A O1 só tem o slot 0: os estágios 1..4 e a via 1 ficam vazios.
        for i in 0 to 4 loop
            write(l, string'(";"));
            if i < NUM_SLOTS then
                write(l, fmt(real(ocup_slot(i)) / real(ciclos)));
            end if;
        end loop;
        slots_via0 := minimum(NUM_SLOTS, 5);
        soma := 0;
        for i in 0 to slots_via0 - 1 loop
            soma := soma + ocup_slot(i);
        end loop;
        write(l, ";" & fmt(real(soma) / real(ciclos * slots_via0)));
        write(l, string'(";"));
        if NUM_SLOTS > 5 then
            slots_via1 := NUM_SLOTS - 5;
            soma := 0;
            for i in 5 to NUM_SLOTS - 1 loop
                soma := soma + ocup_slot(i);
            end loop;
            write(l, fmt(real(soma) / real(ciclos * slots_via1)));
        end if;
        writeline(f_csv, l);
        file_close(f_csv);

        -- 3.6 Encerramento
        report ORG_NOME & ": fim da simulação, " & integer'image(ciclos) & " ciclos, " & integer'image(erros) & " erro(s)";
        fim_sim <= true;
        std.env.stop;
        wait;
    end process;
end architecture;
