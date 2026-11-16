library ieee;
use ieee.std_logic_1164.all;

use work.o1_pkg.all;

entity tb_register_file is
end entity;

architecture test of tb_register_file is
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal write_enable : std_logic := '0';
    signal write_addr   : reg_addr_t := (others => '0');
    signal write_data   : word_t := (others => '0');
    signal read_addr_1  : reg_addr_t := (others => '0');
    signal read_data_1  : word_t;
    signal read_addr_2  : reg_addr_t := (others => '0');
    signal read_data_2  : word_t;
    signal dbg_reg_addr : reg_addr_t := (others => '0');
    signal dbg_reg_data : word_t;
begin
    clk <= not clk after 5 ns;

    dut : entity work.register_file
        port map (
            clk          => clk,
            rst          => rst,
            write_enable => write_enable,
            write_addr   => write_addr,
            write_data   => write_data,
            read_addr_1  => read_addr_1,
            read_data_1  => read_data_1,
            read_addr_2  => read_addr_2,
            read_data_2  => read_data_2,
            dbg_reg_addr => dbg_reg_addr,
            dbg_reg_data => dbg_reg_data
        );

    stimulus : process
    begin
        write_enable <= '1';
        write_addr <= "00001";
        write_data <= x"12345678";
        read_addr_1 <= "00001";
        dbg_reg_addr <= "00001";

        wait until rising_edge(clk);
        wait for 1 ns;
        assert read_data_1 = x"00000000"
            report "Register file wrote before the falling edge"
            severity failure;

        wait until falling_edge(clk);
        wait for 1 ns;
        assert read_data_1 = x"12345678"
            report "Register file did not expose the new value after the falling edge"
            severity failure;
        assert dbg_reg_data = x"12345678"
            report "Debug read did not return the selected register"
            severity failure;
        read_addr_2 <= "00001";
        wait for 1 ns;
        assert read_data_2 = x"12345678"
            report "Second register-file read port did not return the selected register"
            severity failure;

        write_addr <= "00000";
        write_data <= x"FFFFFFFF";
        read_addr_1 <= "00000";
        read_addr_2 <= "00000";
        dbg_reg_addr <= "00000";
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        wait for 1 ns;
        assert read_data_2 = x"00000000" and dbg_reg_data = x"00000000"
            report "Register zero changed after a write attempt"
            severity failure;

        write_enable <= '0';
        write_addr <= "00010";
        write_data <= x"CAFEBABE";
        read_addr_1 <= "00001";
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        wait for 1 ns;
        assert read_data_1 = x"12345678"
            report "Register file changed data while writes were disabled"
            severity failure;

        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        assert read_data_1 = x"00000000"
            report "Synchronous reset did not clear the register file"
            severity failure;
        rst <= '0';

        report "tb_register_file passed" severity note;
        std.env.stop;
        wait;
    end process;
end architecture;
