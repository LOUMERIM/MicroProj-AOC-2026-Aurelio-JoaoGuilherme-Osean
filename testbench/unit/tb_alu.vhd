library ieee;
use ieee.std_logic_1164.all;

use work.o1_pkg.all;

entity tb_alu is
end entity;

architecture test of tb_alu is
    signal operand_a : word_t := (others => '0');
    signal operand_b : word_t := (others => '0');
    signal operation : alu_operation_t := ALU_ADD;
    signal result    : word_t;
    signal zero      : std_logic;
begin
    dut : entity work.alu
        port map (
            operand_a => operand_a,
            operand_b => operand_b,
            operation => operation,
            result    => result,
            zero      => zero
        );

    stimulus : process
    begin
        operand_a <= x"00000005";
        operand_b <= x"00000003";
        operation <= ALU_ADD;
        wait for 1 ns;
        assert result = x"00000008" and zero = '0'
            report "ADD result or Zero flag is incorrect"
            severity failure;

        operation <= ALU_SUB;
        wait for 1 ns;
        assert result = x"00000002" and zero = '0'
            report "SUB result is incorrect"
            severity failure;

        operation <= ALU_AND;
        wait for 1 ns;
        assert result = x"00000001"
            report "AND result is incorrect"
            severity failure;

        operation <= ALU_OR;
        wait for 1 ns;
        assert result = x"00000007"
            report "OR result is incorrect"
            severity failure;

        operand_a <= x"FFFFFFFF";
        operand_b <= x"00000001";
        operation <= ALU_SLT;
        wait for 1 ns;
        assert result = x"00000001"
            report "SLT must compare signed 32-bit operands"
            severity failure;

        operation <= ALU_ADD;
        wait for 1 ns;
        assert result = x"00000000" and zero = '1'
            report "Addition wraparound or Zero flag is incorrect"
            severity failure;

        operand_a <= x"76543210";
        operand_b <= x"76543210";
        operation <= ALU_SUB;
        wait for 1 ns;
        assert result = x"00000000" and zero = '1'
            report "Equal operands must set Zero after subtraction"
            severity failure;

        report "tb_alu passed" severity note;
        std.env.stop;
        wait;
    end process;
end architecture;
