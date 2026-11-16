library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

use work.o1_pkg.all;

-- Memória unificada (R3/R4): um único banco serve as buscas de instrução (IF)
-- e os acessos a dados (MEM). A disputa pelos recursos no mesmo ciclo não é
-- resolvida aqui: o cpu_top_o2 detecta o conflito estrutural e aborta.
entity unified_memory is
    generic (
        DEPTH     : positive := 4096;
        INIT_FILE : string   := ""
    );
    port (
        clk              : in  std_logic;
        if_address       : in  word_t;             -- porta do estágio IF (leitura)
        if_data          : out word_t;
        mem_address      : in  word_t;             -- porta do estágio MEM
        mem_read_enable  : in  std_logic;
        mem_read_data    : out word_t;
        mem_write_enable : in  std_logic;
        mem_write_data   : in  word_t
    );
end entity;

architecture rtl of unified_memory is
    -- Mesma função de carga usada pela instruction_memory (uma palavra
    -- hexadecimal de 32 bits por linha).
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
            report "Cannot open memory image: " & INIT_FILE
            severity failure;
        if open_status /= open_ok then
            return image;
        end if;

        while not endfile(image_file) loop
            readline(image_file, input_line);
            line_number := line_number + 1;
            if input_line.all'length > 0 then
                assert input_line.all'length = 8
                    report "Memory image lines must contain exactly 8 hex digits"
                    severity failure;
                if input_line.all'length /= 8 then
                    exit;
                end if;

                hread(input_line, word_value, good);
                assert good
                    report "Invalid hexadecimal word at line " & natural'image(line_number)
                    severity failure;
                if not good then
                    exit;
                end if;

                assert word_index < DEPTH
                    report "Memory image exceeds configured depth"
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
    -- Porta do IF: leitura assíncrona (mesma semântica da instruction_memory).
    process (all)
        variable word_index : natural;
    begin
        if_data <= (others => '0');
        assert not is_x(if_address)
            report "Unified memory fetch address contains unknown values"
            severity failure;

        if not is_x(if_address) then
            assert if_address(1 downto 0) = "00"
                report "Unified memory fetch address must be word-aligned"
                severity failure;

            if if_address(1 downto 0) = "00" then
                word_index := to_integer(unsigned(if_address(31 downto 2)));
                assert word_index < DEPTH
                    report "Unified memory fetch address is outside configured depth"
                    severity failure;
                if word_index < DEPTH then
                    if_data <= memory(word_index);
                end if;
            end if;
        end if;
    end process;

    -- Porta do MEM: leitura combinacional (mesma semântica da data_memory).
    process (all)
        variable word_index : natural;
    begin
        mem_read_data <= (others => '0');
        if mem_read_enable = '1' then
            assert not is_x(mem_address)
                report "Unified memory data address contains unknown values"
                severity failure;

            if not is_x(mem_address) then
                assert mem_address(1 downto 0) = "00"
                    report "Unified memory data address must be word-aligned"
                    severity failure;

                if mem_address(1 downto 0) = "00" then
                    word_index := to_integer(unsigned(mem_address(31 downto 2)));
                    assert word_index < DEPTH
                        report "Unified memory data address is outside configured depth"
                        severity failure;
                    if word_index < DEPTH then
                        mem_read_data <= memory(word_index);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Porta do MEM: escrita na borda de subida (mesma semântica da data_memory).
    process (clk)
        variable word_index : natural;
    begin
        if rising_edge(clk) and mem_write_enable = '1' then
            assert not is_x(mem_address)
                report "Unified memory write address contains unknown values"
                severity failure;
            assert mem_address(1 downto 0) = "00"
                report "Unified memory write address must be word-aligned"
                severity failure;

            if not is_x(mem_address) and mem_address(1 downto 0) = "00" then
                word_index := to_integer(unsigned(mem_address(31 downto 2)));
                assert word_index < DEPTH
                    report "Unified memory write address is outside configured depth"
                    severity failure;
                if word_index < DEPTH then
                    memory(word_index) <= mem_write_data;
                end if;
            end if;
        end if;
    end process;
end architecture;
