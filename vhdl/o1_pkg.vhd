library ieee;
use ieee.std_logic_1164.all;

package o1_pkg is
    subtype word_t is std_logic_vector(31 downto 0);
    subtype reg_addr_t is std_logic_vector(4 downto 0);
    type word_array_t is array (natural range <>) of word_t;

    type alu_operation_t is (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_SLT);
end package;
