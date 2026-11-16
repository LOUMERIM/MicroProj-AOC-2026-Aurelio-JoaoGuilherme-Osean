library ieee;
use ieee.std_logic_1164.all;

use work.o1_pkg.all;

entity tb_memories is
end entity;

architecture test of tb_memories is
    signal clk          : std_logic := '0';
    signal imem_address : word_t := (others => '0');
    signal instruction  : word_t;
    signal dmem_address : word_t := (others => '0');
    signal read_enable  : std_logic := '0';
    signal write_enable : std_logic := '0';
    signal write_data   : word_t := (others => '0');
    signal read_data    : word_t;
begin
    clk <= not clk after 5 ns;

    imem : entity work.instruction_memory
        generic map (
            DEPTH     => 8,
            INIT_FILE => "tests/fixtures/instructions.hex"
        )
        port map (
            address => imem_address,
            data    => instruction
        );

    dmem : entity work.data_memory
        generic map (
            DEPTH => 8
        )
        port map (
            clk          => clk,
            address      => dmem_address,
            read_enable  => read_enable,
            write_enable => write_enable,
            write_data   => write_data,
            read_data    => read_data
        );

    stimulus : process
    begin
        wait for 1 ns;
        assert instruction = x"20010005"
            report "Instruction memory did not load the first .hex word"
            severity failure;

        imem_address <= x"00000004";
        wait for 1 ns;
        assert instruction = x"20020003"
            report "Instruction memory byte address 4 did not select word 1"
            severity failure;

        imem_address <= x"00000008";
        wait for 1 ns;
        assert instruction = x"00221820"
            report "Instruction memory byte address 8 did not select word 2"
            severity failure;

        dmem_address <= x"00000004";
        read_enable <= '1';
        write_data <= x"DEADBEEF";
        write_enable <= '1';
        wait for 1 ns;
        assert read_data = x"00000000"
            report "Data memory was not initialized to zero"
            severity failure;

        wait until rising_edge(clk);
        wait for 1 ns;
        assert read_data = x"DEADBEEF"
            report "Data memory write/read failed"
            severity failure;

        write_enable <= '0';
        write_data <= x"00000000";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert read_data = x"DEADBEEF"
            report "Data memory changed while writes were disabled"
            severity failure;

        read_enable <= '0';
        wait for 1 ns;
        assert read_data = x"00000000"
            report "Data memory read output was not disabled"
            severity failure;

        report "tb_memories passed" severity note;
        std.env.stop;
        wait;
    end process;
end architecture;
