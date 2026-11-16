library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.o1_pkg.all;

entity register_file is
    port (
        clk          : in  std_logic;
        write_enable : in  std_logic;
        write_addr   : in  reg_addr_t;
        write_data   : in  word_t;
        read_addr_1  : in  reg_addr_t;
        read_data_1  : out word_t;
        read_addr_2  : in  reg_addr_t;
        read_data_2  : out word_t;
        dbg_reg_addr : in  reg_addr_t;
        dbg_reg_data : out word_t
    );
end entity;

architecture rtl of register_file is
    signal registers : word_array_t(0 to 31) := (others => (others => '0'));
begin
    process (clk)
    begin
        if falling_edge(clk) then
            if write_enable = '1' and write_addr /= "00000" then
                registers(to_integer(unsigned(write_addr))) <= write_data;
            end if;
        end if;
    end process;

    read_data_1 <= (others => '0') when read_addr_1 = "00000"
                   else registers(to_integer(unsigned(read_addr_1)));
    read_data_2 <= (others => '0') when read_addr_2 = "00000"
                   else registers(to_integer(unsigned(read_addr_2)));
    dbg_reg_data <= (others => '0') when dbg_reg_addr = "00000"
                    else registers(to_integer(unsigned(dbg_reg_addr)));
end architecture;
