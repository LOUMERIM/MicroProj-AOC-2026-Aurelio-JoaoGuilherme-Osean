.text
# ------------------------------------------------------------------------
# TC — conflito de controle (issue #14)
# Rodar com: make sim ORG=O2 SLOTS=5 PROG=tracos/tc.hex \
#               ESPERADO=tracos/tc_esperado.txt ABORTO=true TIPO=3 PCESP=00000018
#
# Na O2 o beq é resolvido em EX. Quando ele está em EX, as duas instruções
# seguintes já foram buscadas (uma em ID, outra em IF) e, sem flush, seriam
# executadas mesmo com o desvio tomado.
#   0x10: beq NÃO tomado (1 != 2) -> buscar em sequência é o caminho certo,
#         não é conflito; o addi de 0x14 executa normalmente.
#   0x18: beq TOMADO (1 == 1) com 0x1c (ID) e 0x20 (IF) já buscadas
#         -> CONFLITO DE CONTROLE. Sem o aborto, $t5 e $t6 seriam escritos.
# Esperado em O2: hazard_type = 11, hazard_pc = 0x18 (o desvio),
#                 hazard_cycle = 9 (beq buscado no ciclo 7, em EX no ciclo 9).
# Todas as dependências de dados estão a distância >= 3 (sem conflito de dados).
# ------------------------------------------------------------------------
addi $t0, $zero, 1         # 0x00: $t0 = 1
addi $t1, $zero, 2         # 0x04: $t1 = 2
addi $t2, $zero, 1         # 0x08: $t2 = 1
addi $t3, $zero, 0         # 0x0c: espaçador
beq  $t0, $t1, fim         # 0x10: não tomado -> sem conflito
addi $t4, $zero, 9         # 0x14: executa ($t4 = 9)
beq  $t0, $t2, alvo        # 0x18: TOMADO -> CONFLITO DE CONTROLE
addi $t5, $zero, 7         # 0x1c: caminho errado (já em ID)
addi $t6, $zero, 8         # 0x20: caminho errado (já em IF)
alvo:
addi $t7, $zero, 5         # 0x24: alvo do desvio
fim:
break                      # 0x28
