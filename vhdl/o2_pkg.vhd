library ieee;
use ieee.std_logic_1164.all;

use work.o1_pkg.all;

-- Tipos e constantes da organização O2 (pipeline de 5 estágios).
package o2_pkg is
    -- Opcodes/funct compartilhados com a decodificação da O1.
    constant OP_R     : std_logic_vector(5 downto 0) := "000000";
    constant OP_ADDI  : std_logic_vector(5 downto 0) := "001000";
    constant OP_LW    : std_logic_vector(5 downto 0) := "100011";
    constant OP_SW    : std_logic_vector(5 downto 0) := "101011";
    constant OP_BEQ   : std_logic_vector(5 downto 0) := "000100";
    constant FN_BREAK : std_logic_vector(5 downto 0) := "001101";

    -- IF/ID: instrução buscada, disponível no estágio ID.
    type ifid_t is record
        valid : std_logic;
        pc    : word_t;
        instr : word_t;
    end record;

    -- ID/EX: operandos lidos no banco e controles de EX/MEM/WB.
    type idex_t is record
        valid     : std_logic;
        pc_plus4  : word_t;
        rs_value  : word_t;
        rt_value  : word_t;
        imm       : word_t;             -- imediato estendido por sinal
        alu_op    : alu_operation_t;
        use_imm   : std_logic;          -- '1' para I-type e lw/sw
        is_lw     : std_logic;
        is_sw     : std_logic;
        is_beq    : std_logic;
        is_break  : std_logic;
        wb_enable : std_logic;
        wb_addr   : reg_addr_t;
    end record;

    -- EX/MEM: resultado da ALU (endereço, para lw/sw) e controles de memória.
    type exmem_t is record
        valid      : std_logic;
        alu_result : word_t;
        store_data : word_t;            -- valor de rt para sw
        is_lw      : std_logic;
        is_sw      : std_logic;
        is_break   : std_logic;
        wb_enable  : std_logic;
        wb_addr    : reg_addr_t;
    end record;

    -- MEM/WB: dado a escrever no banco de registradores.
    type memwb_t is record
        valid     : std_logic;
        wb_enable : std_logic;
        wb_addr   : reg_addr_t;
        wb_data   : word_t;
        is_break  : std_logic;
    end record;

    -- Instrução é um break (encerra a execução).
    function is_break_instr (instr : word_t) return boolean;
end package;

package body o2_pkg is
    function is_break_instr (instr : word_t) return boolean is
    begin
        return instr(31 downto 26) = OP_R and instr(5 downto 0) = FN_BREAK;
    end function;
end package body;
