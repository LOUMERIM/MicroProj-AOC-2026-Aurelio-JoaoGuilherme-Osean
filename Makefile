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

.PHONY: tabela-t0 diagramas-o2 wave-aborto graficos diagramas all clean run sim compile compile-unit elaborate test-unit serie-s
.PHONY: all clean run sim compile compile-unit elaborate test-unit metricas
.PHONY: all clean run sim compile compile-unit elaborate test-unit wave-t0

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

# Serie S (R5, issue #19): regenera tracos/s005..s200 (.asm, .hex e _esperado.txt)
# a partir do T0. Precisa do MARS: make serie-s MARS_JAR=/caminho/Mars4_5.jar
# Os arquivos gerados ficam versionados; so e preciso rodar de novo se o T0 mudar.
serie-s:
	python3 scripts/gerar_serie_s.py $(if $(MARS_JAR),--mars $(MARS_JAR))
# Metricas do R6 (issue #18): roda cada traco limpo nas duas organizacoes e grava
# metricas.csv na raiz (uma linha por organizacao x traco). Tracos limpos: T0 e a
# serie S (tracos/s*.hex, quando existir), cada um com o seu _esperado.txt.
# O CSV de build/ e truncado no inicio; o tb_cpu escreve o cabecalho em arquivo vazio.
# Qualquer falha de simulacao (registrador divergente do esperado, aborto ou tempo
# esgotado em traco limpo) interrompe o make antes de copiar: metricas.csv nao e
# sobrescrito. A saida de cada execucao fica em build/metricas_run.log.
TRACOS_LIMPOS ?= tracos/t0.hex $(sort $(wildcard tracos/s[0-9]*.hex))
metricas: elaborate
	: > $(BUILD_DIR)/metricas.csv
	@for prog in $(TRACOS_LIMPOS); do \
		esp=$${prog%.hex}_esperado.txt; \
		for org in "O1 1" "O2 5"; do set -- $$org; \
			echo "== $$1 $$prog"; \
			( cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) -gORG_NOME=$$1 -gNUM_SLOTS=$$2 \
				-gPROG_FILE=../$$prog -gESPERADO_FILE=../$$esp --stop-time=$(STOP_TIME) \
				--assert-level=error ) > $(BUILD_DIR)/metricas_run.log 2>&1; \
			rc=$$?; \
			grep -E "fim da simul|error|failure" $(BUILD_DIR)/metricas_run.log; \
			if [ $$rc -ne 0 ]; then \
				echo "ERRO: simulacao de $$1 em $$prog falhou (codigo $$rc); metricas.csv nao foi atualizado"; \
				exit 1; \
			fi; \
		done; \
	done
	cp $(BUILD_DIR)/metricas.csv metricas.csv
	@echo "metricas.csv:"; if command -v column >/dev/null 2>&1; then column -t -s';' metricas.csv; else cat metricas.csv; fi
# Waveform anotada do T0 na O2 (issue #17): simula com dump GHW (guarda os records
# dos registradores entre estagios) e gera em docs/waveforms/ as figuras SVG/PNG,
# a tabela ciclo a ciclo (CSV) e a sessao do GTKWave (.gtkw).
# Abrir no GTKWave: gtkwave build/t0_o2.ghw docs/waveforms/t0_o2.gtkw
WAVE_DIR = docs/waveforms
wave-t0: elaborate
	cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) -gORG_NOME=O2 -gNUM_SLOTS=5 \
		-gPROG_FILE=../tracos/t0.hex -gESPERADO_FILE=../tracos/t0_esperado.txt \
		--stop-time=$(STOP_TIME) --wave=t0_o2.ghw
	python3 scripts/waveform_o2.py $(BUILD_DIR)/t0_o2.ghw tracos/t0.asm $(WAVE_DIR) t0_o2
	@if command -v magick >/dev/null 2>&1; then \
		for f in $(WAVE_DIR)/t0_o2_*.svg; do magick -density 110 $$f $${f%.svg}.png; done; \
	else echo "(ImageMagick ausente: PNGs nao gerados; os SVGs abrem no navegador)"; fi

# Diagramas instrucao x ciclo do T0 (issue #22): simula o T0 na O1 e na O2 com dump GHW e
# gera docs/diagrama-instrucao-ciclo.md (10 primeiras e 3 ultimas instrucoes, formato 6.1)
# e as tabelas completas em docs/diagramas/. Usa o ghwdump (vem com o GHDL).
diagramas: elaborate
	cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) -gORG_NOME=O1 -gNUM_SLOTS=1 \
		-gPROG_FILE=../tracos/t0.hex -gESPERADO_FILE=../tracos/t0_esperado.txt \
		--stop-time=$(STOP_TIME) --wave=t0_o1.ghw
	cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) -gORG_NOME=O2 -gNUM_SLOTS=5 \
		-gPROG_FILE=../tracos/t0.hex -gESPERADO_FILE=../tracos/t0_esperado.txt \
		--stop-time=$(STOP_TIME) --wave=t0_o2.ghw
	python3 scripts/diagrama_instr_ciclo.py $(BUILD_DIR)/t0_o1.ghw $(BUILD_DIR)/t0_o2.ghw tracos/t0.asm docs

# Graficos do relatorio (issue #23): CPI por organizacao, speedup medido x ideal e
# speedup x tamanho (eixo x log), em SVG a partir do metricas.csv (sem dependencias).
# PNG opcional com ImageMagick. O run_all ja gera tudo; este alvo so redesenha.
graficos:
	python3 scripts/graficos.py metricas.csv resultados/graficos
	@if command -v magick >/dev/null 2>&1; then \
		for f in resultados/graficos/*.svg; do magick -density 150 $$f $${f%.svg}.png; done; fi

# Tabela do T0 (endereco, registradores lidos e escritos, distancia ao produtor): docs/tabela-t0.md.
tabela-t0:
	python3 scripts/tabela_t0.py tracos/t0.asm docs/tabela-t0.md

# Diagramas da O2 (caminho de dados, unidade de deteccao e campos dos registradores entre
# estagios com a largura em bits), lidos de vhdl/o2_pkg.vhd e cpu_top_o2.vhd: docs/diagramas-o2.md.
diagramas-o2:
	python3 scripts/diagramas_o2.py vhdl docs
	@if command -v magick >/dev/null 2>&1; then \
		for f in docs/diagramas/o2_*.svg; do magick -density 100 $$f $${f%.svg}.png; done; fi

# Waveform de deteccao e aborto de cada conflito (TD, TE, TC) na O2, anotada no ciclo exato:
# docs/waveforms/<traco>_aborto.{svg,png,csv,gtkw}. Abrir no GTKWave:
#   gtkwave build/td_o2.ghw docs/waveforms/td_aborto.gtkw
wave-aborto: elaborate
	@for spec in "td 1 false 00000014 dados" "te 2 true 00000018 estrutural" "tc 3 false 00000018 controle"; do \
		set -- $$spec; \
		echo "== $$1"; \
		pc=$$(python3 -c "print(format(int('$$4',16),'032b'))"); \
		( cd $(BUILD_DIR) && ghdl -r $(GHDL_FLAGS) $(TESTBENCH) -gORG_NOME=O2 -gNUM_SLOTS=5 \
			-gPROG_FILE=../tracos/$$1.hex -gESPERADO_FILE=../tracos/$$1_esperado.txt -gESPERA_ABORTO=true \
			-gTIPO_ESPERADO=$$2 -gMEM_UNIFICADA=$$3 -gPC_ESPERADO=$$pc --stop-time=$(STOP_TIME) \
			--wave=$$1_o2.ghw ) </dev/null > $(BUILD_DIR)/wave_aborto.log 2>&1; \
		rc=$$?; grep -E "ABORTO|error|failure" $(BUILD_DIR)/wave_aborto.log; \
		if [ $$rc -ne 0 ]; then echo "ERRO: simulacao de $$1 falhou"; exit 1; fi; \
		python3 scripts/waveform_aborto.py $(BUILD_DIR)/$$1_o2.ghw tracos/$$1.asm docs/waveforms $$1 $$5 || exit 1; \
		if command -v magick >/dev/null 2>&1; then magick -density 100 docs/waveforms/$$1_aborto.svg docs/waveforms/$$1_aborto.png; fi; \
	done

clean:
	rm -rf $(BUILD_DIR)
