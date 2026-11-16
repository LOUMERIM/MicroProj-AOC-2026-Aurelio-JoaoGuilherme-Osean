library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.o1_pkg.all;

entity alu is
    port (
        operand_a : in  word_t;
        operand_b : in  word_t;
        operation : in  alu_operation_t;
        result    : out word_t;
        zero      : out std_logic
    );
end entity;

architecture rtl of alu is
begin
    process (all)
        variable result_value : word_t;
    begin
        case operation is
            when ALU_ADD =>
                result_value := std_logic_vector(unsigned(operand_a) + unsigned(operand_b));
            when ALU_SUB =>
                result_value := std_logic_vector(unsigned(operand_a) - unsigned(operand_b));
            when ALU_AND =>
                result_value := operand_a and operand_b;
            when ALU_OR =>
                result_value := operand_a or operand_b;
            when ALU_SLT =>
                result_value := (others => '0');
                if signed(operand_a) < signed(operand_b) then
                    result_value(0) := '1';
                end if;
        end case;

        result <= result_value;
    end process;

    zero <= '1' when result = x"00000000" else '0';
end architecture;
