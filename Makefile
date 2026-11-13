# Makefile for MicroProj-AOC

# Directories
VHDL_DIR = vhdl
TB_DIR = testbench
BUILD_DIR = build

# Files
SOURCES = $(wildcard $(VHDL_DIR)/*.vhd)
TESTBENS = $(wildcard $(TB_DIR)/*.vhd)

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

# Limite de tempo simulado: protege contra simulacao infinita (e arquivo de onda gigante).
# O testbench ja para sozinho (std.env.stop); isto e so uma rede de seguranca.
# Para simular mais tempo: make sim STOP_TIME=1ms
STOP_TIME ?= 200us

# O GHDL roda DENTRO de build/ com caminhos relativos (../vhdl/...), assim tudo que ele gera
# fica em build/ e o arquivo work-obj08.cf nao grava o caminho absoluto da pasta
# (que quebra o GHDL quando o caminho tem acentos, como "COMPUTAÇÂO").

.PHONY: all clean run sim compile elaborate

all: $(BUILD_DIR) $(SOURCES)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile all VHDL files
compile: $(BUILD_DIR)
	cd $(BUILD_DIR) && ghdl -a $(GHDL_FLAGS) $(addprefix ../,$(SOURCES))
	cd $(BUILD_DIR) && ghdl -a $(GHDL_FLAGS) $(addprefix ../,$(TESTBENS))

# Elaborate the testbench
elaborate: compile
	cd $(BUILD_DIR) && ghdl -e $(GHDL_FLAGS) $(TESTBENCH)

# Run the simulation and produce a compact GHW waveform (abre no GTKWave)
run: elaborate
	cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) $(GENERICS) --stop-time=$(STOP_TIME) --wave=$(WAVE_FILE)

# Simpler target for development: compile and run
sim: compile elaborate run

clean:
	rm -rf $(BUILD_DIR)
