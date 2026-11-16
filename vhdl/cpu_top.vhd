library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.o1_pkg.all;

entity cpu_top is
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

architecture rtl of cpu_top is
    type state_t is (
        FETCH,
        DECODE,
        R_EXEC,
        R_WB,
        ADDI_EXEC,
        ADDI_WB,
        ADDR,
        MEM_READ,
        MEM_WB,
        MEM_WRITE,
        BRANCH,
        HALT
    );

    constant OP_R     : std_logic_vector(5 downto 0) := "000000";
    constant OP_ADDI  : std_logic_vector(5 downto 0) := "001000";
    constant OP_LW    : std_logic_vector(5 downto 0) := "100011";
    constant OP_SW    : std_logic_vector(5 downto 0) := "101011";
    constant OP_BEQ   : std_logic_vector(5 downto 0) := "000100";
    constant FN_BREAK : std_logic_vector(5 downto 0) := "001101";

    signal state             : state_t := FETCH;
    signal pc                : word_t := (others => '0');
    signal instruction       : word_t;
    signal instruction_reg   : word_t := (others => '0');
    signal operand_a_reg     : word_t := (others => '0');
    signal operand_b_reg     : word_t := (others => '0');
    signal alu_out_reg       : word_t := (others => '0');
    signal memory_data_reg   : word_t := (others => '0');
    signal register_read_a   : word_t;
    signal register_read_b   : word_t;
    signal alu_operand_a     : word_t;
    signal alu_operand_b     : word_t;
    signal alu_result        : word_t;
    signal alu_zero          : std_logic;
    signal alu_operation     : alu_operation_t := ALU_ADD;
    signal data_memory_read  : word_t;
    signal register_write_en : std_logic := '0';
    signal register_write_to : reg_addr_t := (others => '0');
    signal register_write_dt : word_t := (others => '0');
    signal data_read_en      : std_logic;
    signal data_write_en     : std_logic;
    signal done_reg          : std_logic := '0';
    signal retired_pulse     : std_logic := '0';
    signal instruction_valid : std_logic := '0';
begin
    instruction_store : entity work.instruction_memory
        generic map (
            DEPTH     => 4096,
            INIT_FILE => PROG_FILE
        )
        port map (
            address => pc,
            data    => instruction
        );

    registers : entity work.register_file
        port map (
            clk          => clk,
            rst          => rst,
            write_enable => register_write_en,
            write_addr   => register_write_to,
            write_data   => register_write_dt,
            read_addr_1  => instruction_reg(25 downto 21),
            read_data_1  => register_read_a,
            read_addr_2  => instruction_reg(20 downto 16),
            read_data_2  => register_read_b,
            dbg_reg_addr => dbg_reg_addr,
            dbg_reg_data => dbg_reg_data
        );

    arithmetic_logic_unit : entity work.alu
        port map (
            operand_a => alu_operand_a,
            operand_b => alu_operand_b,
            operation => alu_operation,
            result    => alu_result,
            zero      => alu_zero
        );

    data_store : entity work.data_memory
        generic map (
            DEPTH => 256
        )
        port map (
            clk          => clk,
            address      => alu_out_reg,
            read_enable  => data_read_en,
            write_enable => data_write_en,
            write_data   => operand_b_reg,
            read_data    => data_memory_read
        );

    process (all)
        variable sign_extended_immediate : word_t;
    begin
        sign_extended_immediate := std_logic_vector(resize(signed(instruction_reg(15 downto 0)), 32));
        alu_operand_a <= (others => '0');
        alu_operand_b <= (others => '0');
        alu_operation <= ALU_ADD;

        case state is
            when FETCH =>
                alu_operand_a <= pc;
                alu_operand_b <= x"00000004";
            when DECODE =>
                alu_operand_a <= pc;
                alu_operand_b <= std_logic_vector(shift_left(signed(sign_extended_immediate), 2));
            when R_EXEC =>
                alu_operand_a <= operand_a_reg;
                alu_operand_b <= operand_b_reg;
                case instruction_reg(5 downto 0) is
                    when "100000" => alu_operation <= ALU_ADD;
                    when "100010" => alu_operation <= ALU_SUB;
                    when "100100" => alu_operation <= ALU_AND;
                    when "100101" => alu_operation <= ALU_OR;
                    when "101010" => alu_operation <= ALU_SLT;
                    when others   => alu_operation <= ALU_ADD;
                end case;
            when ADDI_EXEC | ADDR =>
                alu_operand_a <= operand_a_reg;
                alu_operand_b <= sign_extended_immediate;
            when BRANCH =>
                alu_operand_a <= operand_a_reg;
                alu_operand_b <= operand_b_reg;
                alu_operation <= ALU_SUB;
            when others =>
                null;
        end case;
    end process;

    data_read_en <= '1' when state = MEM_READ else '0';
    data_write_en <= '1' when state = MEM_WRITE else '0';

    done <= done_reg;
    hazard_abort <= '0';
    hazard_type <= "00";
    hazard_pc <= (others => '0');
    hazard_cycle <= (others => '0');
    retired <= (0 => retired_pulse, others => '0');
    stage_valid <= (0 => (instruction_valid or retired_pulse), others => '0');

    process (clk)
        variable opcode : std_logic_vector(5 downto 0);
        variable funct  : std_logic_vector(5 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= FETCH;
                pc <= (others => '0');
                instruction_reg <= (others => '0');
                operand_a_reg <= (others => '0');
                operand_b_reg <= (others => '0');
                alu_out_reg <= (others => '0');
                memory_data_reg <= (others => '0');
                register_write_en <= '0';
                register_write_to <= (others => '0');
                register_write_dt <= (others => '0');
                done_reg <= '0';
                retired_pulse <= '0';
                instruction_valid <= '0';
            else
                register_write_en <= '0';
                retired_pulse <= '0';

                case state is
                    when FETCH =>
                        instruction_reg <= instruction;
                        pc <= alu_result;
                        instruction_valid <= '1';
                        state <= DECODE;

                    when DECODE =>
                        operand_a_reg <= register_read_a;
                        operand_b_reg <= register_read_b;
                        alu_out_reg <= alu_result;
                        opcode := instruction_reg(31 downto 26);
                        funct := instruction_reg(5 downto 0);

                        if opcode = OP_R then
                            if funct = FN_BREAK then
                                done_reg <= '1';
                                instruction_valid <= '0';
                                state <= HALT;
                            elsif funct = "100000" or funct = "100010" or
                                  funct = "100100" or funct = "100101" or
                                  funct = "101010" then
                                state <= R_EXEC;
                            else
                                assert false
                                    report "Unsupported R-format function code"
                                    severity failure;
                                state <= HALT;
                            end if;
                        elsif opcode = OP_ADDI then
                            state <= ADDI_EXEC;
                        elsif opcode = OP_LW or opcode = OP_SW then
                            state <= ADDR;
                        elsif opcode = OP_BEQ then
                            state <= BRANCH;
                        else
                            assert false
                                report "Unsupported instruction opcode"
                                severity failure;
                            state <= HALT;
                        end if;

                    when R_EXEC =>
                        alu_out_reg <= alu_result;
                        state <= R_WB;

                    when R_WB =>
                        register_write_en <= '1';
                        register_write_to <= instruction_reg(15 downto 11);
                        register_write_dt <= alu_out_reg;
                        retired_pulse <= '1';
                        instruction_valid <= '0';
                        state <= FETCH;

                    when ADDI_EXEC =>
                        alu_out_reg <= alu_result;
                        state <= ADDI_WB;

                    when ADDI_WB =>
                        register_write_en <= '1';
                        register_write_to <= instruction_reg(20 downto 16);
                        register_write_dt <= alu_out_reg;
                        retired_pulse <= '1';
                        instruction_valid <= '0';
                        state <= FETCH;

                    when ADDR =>
                        alu_out_reg <= alu_result;
                        if instruction_reg(31 downto 26) = OP_LW then
                            state <= MEM_READ;
                        else
                            state <= MEM_WRITE;
                        end if;

                    when MEM_READ =>
                        memory_data_reg <= data_memory_read;
                        state <= MEM_WB;

                    when MEM_WB =>
                        register_write_en <= '1';
                        register_write_to <= instruction_reg(20 downto 16);
                        register_write_dt <= memory_data_reg;
                        retired_pulse <= '1';
                        instruction_valid <= '0';
                        state <= FETCH;

                    when MEM_WRITE =>
                        retired_pulse <= '1';
                        instruction_valid <= '0';
                        state <= FETCH;

                    when BRANCH =>
                        if alu_zero = '1' then
                            pc <= alu_out_reg;
                        end if;
                        retired_pulse <= '1';
                        instruction_valid <= '0';
                        state <= FETCH;

                    when HALT =>
                        done_reg <= '1';
                        instruction_valid <= '0';
                        state <= HALT;
                end case;
            end if;
        end if;
    end process;

    -- R3 requires MEM_UNIFICADA for all organizations; O1 always keeps separate memories.
    assert not MEM_UNIFICADA
        report "O1 uses separate instruction and data memories"
        severity warning;
end architecture;
