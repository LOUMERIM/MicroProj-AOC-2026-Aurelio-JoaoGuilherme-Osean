library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_cpu is
    generic (
        PROG_FILE          : string := "tracos/t0.hex";
        ESPERADO_FILE      : string := "tracos/t0_esperado.txt";
        ORG_NOME           : string := "O1";
        NUM_SLOTS          : positive := 1;
        MEM_UNIFICADA      : boolean := false;
        ESPERA_ABORTO      : boolean := false;
        TIPO_ESPERADO      : natural := 0;
        T_CLK              : time := 10 ns;
        MAX_CICLOS         : natural := 10_000;
        INSTR_ESPERADAS    : natural := 30;
        CICLOS_ESPERADOS   : natural := 0;
        VERIFICA_HAZARD_PC : boolean := false;
        HAZARD_PC_ESPERADO : std_logic_vector(31 downto 0) := (others => '0')
    );
end entity;

architecture sim of tb_cpu is
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal fim_sim      : boolean := false;
    signal done         : std_logic;
    signal hazard_abort : std_logic;
    signal hazard_type  : std_logic_vector(1 downto 0);
    signal hazard_pc    : std_logic_vector(31 downto 0);
    signal hazard_cycle : unsigned(31 downto 0);
    signal retired      : unsigned(1 downto 0);
    signal stage_valid  : std_logic_vector(9 downto 0);
    signal dbg_reg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_reg_data : std_logic_vector(31 downto 0);
begin
    clk <= not clk after T_CLK / 2 when not fim_sim else '0';

    dut : entity work.cpu_top
        generic map (
            PROG_FILE     => PROG_FILE,
            MEM_UNIFICADA => MEM_UNIFICADA
        )
        port map (
            clk          => clk,
            rst          => rst,
            done         => done,
            hazard_abort => hazard_abort,
            hazard_type  => hazard_type,
            hazard_pc    => hazard_pc,
            hazard_cycle => hazard_cycle,
            retired      => retired,
            stage_valid  => stage_valid,
            dbg_reg_addr => dbg_reg_addr,
            dbg_reg_data => dbg_reg_data
        );

    principal : process
        file f_esp : text;
        file f_csv : text;
        variable l : line;
        variable st : file_open_status;
        variable ciclos : natural := 0;
        variable instrs : natural := 0;
        variable ocupados : natural := 0;
        variable erros : natural := 0;
        variable reg_num : integer;
        variable valor : std_logic_vector(31 downto 0);
        variable cpi : real := 0.0;
        variable ipc : real := 0.0;
        variable ocup : real := 0.0;
        variable good : boolean;
    begin
        assert NUM_SLOTS = 1
            report "O1 tb_cpu must count exactly one slot"
            severity failure;
        assert MAX_CICLOS > 0
            report "MAX_CICLOS must be greater than zero"
            severity failure;

        rst <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';

        loop
            wait until falling_edge(clk);
            ciclos := ciclos + 1;
            instrs := instrs + to_integer(retired);
            for i in 0 to NUM_SLOTS - 1 loop
                if stage_valid(i) = '1' then
                    ocupados := ocupados + 1;
                end if;
            end loop;

            assert stage_valid(9 downto 1) = "000000000"
                report "O1 must use only stage_valid(0)"
                severity failure;

            exit when done = '1' or hazard_abort = '1' or ciclos >= MAX_CICLOS;
        end loop;

        if hazard_abort = '1' then
            report ORG_NOME & ": ABORTO tipo=" & to_string(hazard_type) &
                   " pc=0x" & to_hstring(hazard_pc) &
                   " ciclo=" & integer'image(to_integer(hazard_cycle));
            assert ESPERA_ABORTO
                report "Aborto inesperado: o traço deveria terminar normalmente"
                severity failure;
            assert to_integer(unsigned(hazard_type)) = TIPO_ESPERADO
                report "Tipo de conflito diferente do esperado"
                severity failure;
            assert to_integer(hazard_cycle) = ciclos
                report "hazard_cycle difere da contagem do testbench"
                severity failure;
            if VERIFICA_HAZARD_PC then
                assert hazard_pc = HAZARD_PC_ESPERADO
                    report "hazard_pc difere do PC esperado"
                    severity failure;
            end if;
        elsif done = '1' then
            assert not ESPERA_ABORTO
                report "O traço deveria ter produzido um aborto"
                severity failure;
            assert hazard_abort = '0' and hazard_type = "00" and
                   hazard_pc = x"00000000" and
                   hazard_cycle = to_unsigned(0, hazard_cycle'length)
                report "Sinais hazard_* devem permanecer em zero na O1"
                severity failure;
            assert instrs = INSTR_ESPERADAS
                report "Quantidade de instruções úteis aposentadas difere do esperado"
                severity failure;
            assert ocupados > 0
                report "stage_valid não marcou nenhuma ocupação do slot O1"
                severity failure;
            if CICLOS_ESPERADOS > 0 then
                assert ciclos = CICLOS_ESPERADOS
                    report "Quantidade de ciclos difere do esperado"
                    severity failure;
            end if;

            -- R3 has no data-memory debug port; T0 checks sw/lw through these register results.
            file_open(st, f_esp, ESPERADO_FILE, read_mode);
            assert st = open_ok
                report "Não foi possível abrir " & ESPERADO_FILE
                severity failure;

            while not endfile(f_esp) loop
                readline(f_esp, l);
                if l.all'length > 0 then
                    if l.all(1) /= '#' then
                        read(l, reg_num, good);
                        assert good and reg_num >= 0 and reg_num <= 31
                            report "Linha inválida no arquivo esperado: índice de registrador"
                            severity failure;
                        hread(l, valor, good);
                        assert good
                            report "Linha inválida no arquivo esperado: valor hexadecimal"
                            severity failure;

                        if good and reg_num >= 0 and reg_num <= 31 then
                            dbg_reg_addr <= std_logic_vector(to_unsigned(reg_num, dbg_reg_addr'length));
                            wait for 1 ns;
                            assert done = '1' and retired = to_unsigned(0, retired'length)
                                report "A CPU não permaneceu congelada após done"
                                severity failure;
                            if dbg_reg_data /= valor then
                                erros := erros + 1;
                                report "Reg " & integer'image(reg_num) &
                                       ": esperado 0x" & to_hstring(valor) &
                                       ", obtido 0x" & to_hstring(dbg_reg_data)
                                    severity error;
                            end if;
                        end if;
                    end if;
                end if;
            end loop;
            file_close(f_esp);

            assert erros = 0
                report "Um ou mais registradores diferem dos valores esperados"
                severity failure;
        else
            report ORG_NOME & ": tempo esgotado em " & integer'image(MAX_CICLOS) &
                   " ciclos"
                severity failure;
        end if;

        if instrs > 0 then
            cpi := real(ciclos) / real(instrs);
            ipc := real(instrs) / real(ciclos);
        end if;
        if ciclos > 0 then
            ocup := real(ocupados) / real(ciclos * NUM_SLOTS);
        end if;

        file_open(st, f_csv, "metricas.csv", append_mode);
        assert st = open_ok
            report "Não foi possível abrir metricas.csv para escrita"
            severity failure;
        write(l, ORG_NOME & ";" & PROG_FILE & ";" & integer'image(ciclos) & ";" &
                 integer'image(instrs) & ";" & real'image(cpi) & ";" &
                 real'image(ipc) & ";" & real'image(ocup) & ";" &
                 integer'image(erros));
        writeline(f_csv, l);
        file_close(f_csv);

        report ORG_NOME & ": fim da simulação, " & integer'image(ciclos) &
               " ciclos, " & integer'image(instrs) & " instruções úteis, " &
               integer'image(erros) & " erro(s)";
        fim_sim <= true;
        std.env.stop;
        wait;
    end process;
end architecture;
