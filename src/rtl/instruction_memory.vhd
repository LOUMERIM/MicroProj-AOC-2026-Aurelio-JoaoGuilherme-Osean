library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

use work.o1_pkg.all;

entity instruction_memory is
    generic (
        DEPTH     : positive := 256;
        INIT_FILE : string   := ""
    );
    port (
        address : in  word_t;
        data    : out word_t
    );
end entity;

architecture rtl of instruction_memory is
    impure function load_image return word_array_t is
        variable image       : word_array_t(0 to DEPTH - 1) := (others => x"00000000");
        file image_file      : text;
        variable open_status : file_open_status;
        variable input_line  : line;
        variable word_value  : word_t;
        variable good        : boolean;
        variable word_index  : natural := 0;
        variable line_number : natural := 0;
    begin
        if INIT_FILE'length = 0 then
            return image;
        end if;

        file_open(open_status, image_file, INIT_FILE, read_mode);
        assert open_status = open_ok
            report "Cannot open instruction image: " & INIT_FILE
            severity failure;
        if open_status /= open_ok then
            return image;
        end if;

        while not endfile(image_file) loop
            readline(image_file, input_line);
            line_number := line_number + 1;
            if input_line.all'length > 0 then
                assert input_line.all'length = 8
                    report "Instruction image lines must contain exactly 8 hex digits"
                    severity failure;
                if input_line.all'length /= 8 then
                    exit;
                end if;

                hread(input_line, word_value, good);
                assert good
                    report "Invalid hexadecimal instruction at line " & natural'image(line_number)
                    severity failure;
                if not good then
                    exit;
                end if;

                assert word_index < DEPTH
                    report "Instruction image exceeds configured memory depth"
                    severity failure;
                if word_index >= DEPTH then
                    exit;
                end if;

                image(word_index) := word_value;
                word_index := word_index + 1;
            end if;
        end loop;

        file_close(image_file);
        return image;
    end function;

    signal memory : word_array_t(0 to DEPTH - 1) := load_image;
begin
    process (all)
        variable word_index : natural;
    begin
        data <= (others => '0');
        assert not is_x(address)
            report "Instruction memory address contains unknown values"
            severity failure;

        if not is_x(address) then
            assert address(1 downto 0) = "00"
                report "Instruction memory address must be word-aligned"
                severity failure;

            if address(1 downto 0) = "00" then
                word_index := to_integer(unsigned(address(31 downto 2)));
                assert word_index < DEPTH
                    report "Instruction memory address is outside configured depth"
                    severity failure;
                if word_index < DEPTH then
                    data <= memory(word_index);
                end if;
            end if;
        end if;
    end process;
end architecture;
