# Makefile for MicroProj-AOC

# Directories
VHDL_DIR = vhdl
TB_DIR = testbench
BUILD_DIR = build

# Keep package declarations before units that import them; wildcard order is not
# a valid dependency order for VHDL analysis.
SOURCES = $(VHDL_DIR)/o1_pkg.vhd \
          $(VHDL_DIR)/o2_pkg.vhd \
          $(VHDL_DIR)/register_file.vhd \
          $(VHDL_DIR)/alu.vhd \
          $(VHDL_DIR)/instruction_memory.vhd \
          $(VHDL_DIR)/data_memory.vhd \
          $(VHDL_DIR)/unified_memory.vhd \
          $(VHDL_DIR)/cpu_top.vhd \
          $(VHDL_DIR)/cpu_top_o2.vhd
TESTBENS = $(TB_DIR)/tb_cpu.vhd
UNIT_TESTBENS = $(TB_DIR)/unit/tb_register_file.vhd \
                $(TB_DIR)/unit/tb_alu.vhd \
                $(TB_DIR)/unit/tb_memories.vhd
UNIT_TESTS = tb_register_file tb_alu tb_memories

# Targets
TESTBENCH = tb_cpu
WAVE_FILE = $(TESTBENCH).ghw

# VHDL-2008 (exigido pelo enunciado)
GHDL_FLAGS = --std=08

# Parametros do testbench (generics). Padrao: organizacao O1 (multiciclo) no traco T0.
# O GHDL roda dentro de build/, entao os caminhos dos tracos usam ../
# Exemplos:
#   make sim                                      -> O1, tracos/t0.hex
#   make sim ORG=O2 SLOTS=5                       -> O2 (pipeline)
#   make sim PROG=tracos/td.hex ESPERADO=tracos/td_esperado.txt ABORTO=true TIPO=1
ORG      ?= O1
SLOTS    ?= 1
PROG     ?= tracos/t0.hex
ESPERADO ?= tracos/t0_esperado.txt
ABORTO   ?= false
TIPO     ?= 0
MEMUNI   ?= false

GENERICS = -gORG_NOME=$(ORG) -gNUM_SLOTS=$(SLOTS) \
           -gPROG_FILE=../$(PROG) -gESPERADO_FILE=../$(ESPERADO) \
           -gESPERA_ABORTO=$(ABORTO) -gTIPO_ESPERADO=$(TIPO) -gMEM_UNIFICADA=$(MEMUNI)

# PC esperado do aborto (issue #15): com PCESP configurado, divergencia em
# hazard_pc falha a simulacao. Passe o valor em hexadecimal, sem 0x, ex.:
#   make sim ... PCESP=00000018
# (o GHDL so aceita std_logic_vector em binario na linha de comando, entao convertemos)
PCESP ?=
ifneq ($(PCESP),)
GENERICS += -gPC_ESPERADO=$(shell python3 -c 'print(format(int("$(PCESP)", 16), "032b"))')
endif

# Limite de tempo simulado: protege contra simulacao infinita (e arquivo de onda gigante).
# O testbench ja para sozinho (std.env.stop); isto e so uma rede de seguranca.
# Para simular mais tempo: make sim STOP_TIME=1ms
STOP_TIME ?= 200us

# O GHDL roda DENTRO de build/ com caminhos relativos (../vhdl/...), assim tudo que ele gera
# fica em build/ e o arquivo work-obj08.cf nao grava o caminho absoluto da pasta
# (que quebra o GHDL quando o caminho tem acentos, como "COMPUTAÇÂO").

.PHONY: all clean run sim compile compile-unit elaborate test-unit

all: $(BUILD_DIR) $(SOURCES)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile the RTL in dependency order, then the single integration testbench.
compile: $(BUILD_DIR)
	cd $(BUILD_DIR) && ghdl -a $(GHDL_FLAGS) $(addprefix ../,$(SOURCES))
	cd $(BUILD_DIR) && ghdl -a $(GHDL_FLAGS) $(addprefix ../,$(TESTBENS))

compile-unit: compile
	cd $(BUILD_DIR) && ghdl -a $(GHDL_FLAGS) $(addprefix ../,$(UNIT_TESTBENS))

# Elaborate the testbench
elaborate: compile
	cd $(BUILD_DIR) && ghdl -e $(GHDL_FLAGS) $(TESTBENCH)

# Run the simulation and produce a compact GHW waveform (abre no GTKWave)
run: elaborate
	cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) $(GENERICS) --stop-time=$(STOP_TIME) --wave=$(WAVE_FILE)

# Simpler target for development: compile and run
sim: run

test-unit: compile-unit
	cd $(BUILD_DIR) && for tb in $(UNIT_TESTS); do \
		ghdl -e $(GHDL_FLAGS) $$tb && \
		ghdl -r $(GHDL_FLAGS) $$tb --assert-level=error || exit $$?; \
	done

clean:
	rm -rf $(BUILD_DIR)
