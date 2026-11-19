library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.o1_pkg.all;

entity data_memory is
    generic (
        DEPTH : positive := 256
    );
    port (
        clk          : in  std_logic;
        address      : in  word_t;
        read_enable  : in  std_logic;
        write_enable : in  std_logic;
        write_data   : in  word_t;
        read_data    : out word_t
    );
end entity;

architecture rtl of data_memory is
    signal memory : word_array_t(0 to DEPTH - 1) := (others => (others => '0'));
begin
    process (all)
        variable word_index : natural;
    begin
        read_data <= (others => '0');
        if read_enable = '1' then
            assert not is_x(address)
                report "Data memory address contains unknown values"
                severity failure;

            if not is_x(address) then
                assert address(1 downto 0) = "00"
                    report "Data memory address must be word-aligned"
                    severity failure;

                if address(1 downto 0) = "00" then
                    word_index := to_integer(unsigned(address(31 downto 2)));
                    assert word_index < DEPTH
                        report "Data memory address is outside configured depth"
                        severity failure;
                    if word_index < DEPTH then
                        read_data <= memory(word_index);
                    end if;
                end if;
            end if;
        end if;
    end process;

    process (clk)
        variable word_index : natural;
    begin
        if rising_edge(clk) and write_enable = '1' then
            assert not is_x(address)
                report "Data memory write address contains unknown values"
                severity failure;
            assert address(1 downto 0) = "00"
                report "Data memory write address must be word-aligned"
                severity failure;

            if not is_x(address) and address(1 downto 0) = "00" then
                word_index := to_integer(unsigned(address(31 downto 2)));
                assert word_index < DEPTH
                    report "Data memory write address is outside configured depth"
                    severity failure;
                if word_index < DEPTH then
                    memory(word_index) <= write_data;
                end if;
            end if;
        end if;
    end process;
end architecture;
