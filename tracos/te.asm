.text
# ------------------------------------------------------------------------
# TE — conflito estrutural com memória unificada (issue #13)
# Rodar com: make sim ORG=O2 SLOTS=5 PROG=tracos/te.hex \
#               ESPERADO=tracos/te_esperado.txt ABORTO=true TIPO=2 MEMUNI=true
#
# Com MEM_UNIFICADA = true, o sw entra no estágio MEM no mesmo ciclo em que
# a 3ª instrução seguinte está em IF (distância IF -> MEM = 3 estágios).
# A instrução mais antiga (sw, em MEM) mantém o acesso; a mais nova (em IF)
# não obteve o recurso e é abortada: hazard_type = 10, hazard_pc = 0x18,
# hazard_cycle = 7.
# ------------------------------------------------------------------------
addi $t0, $zero, 0x78      # 0x00: $t0 = 0x78
addi $t1, $zero, 0x9a      # 0x04
addi $t2, $zero, 0xbc      # 0x08
sw   $t0, 0x100($zero)     # 0x0c: em MEM no ciclo 7 -> conflito estrutural
addi $t3, $zero, 1         # 0x10
addi $t4, $zero, 2         # 0x14
addi $t5, $zero, 3         # 0x18: em IF no ciclo 7 -> abortada (hazard_pc)break                      # 0x1c (não é alcançado)
