.text
# ------------------------------------------------------------------------
# TD — conflito de dados RAW (issue #12)
# Rodar com: make sim ORG=O2 SLOTS=5 PROG=tracos/td.hex \
#               ESPERADO=tracos/td_esperado.txt ABORTO=true TIPO=1 PCESP=00000014
#
# As três primeiras dependências NÃO são conflito e não podem abortar:
#   0x04 -> 0x08: escrita em $zero não gera dependência (R1).
#   0x00 -> 0x0c: distância 3 — $t0 é escrito em WB na 1ª metade do ciclo e
#                 lido em ID na 2ª metade do mesmo ciclo (R2).
# O conflito real (o sub em 0x14 tem DUAS dependências a distância <= 2, as duas
# detectadas no mesmo ciclo):
#   0x10 -> 0x14: distância 1 — o sub está em ID lendo $t3 (rs) enquanto o addi
#                 que o produz ainda está em EX. Sem o aborto, o sub leria
#                 $t3 = 0 e $t4 ficaria -10 em vez de -7.
#   0x0c -> 0x14: distância 2 — o sub lê também $t2 (rt), que o add de 0x0c
#                 ainda está em MEM.
# Esperado em O2: hazard_type = 01, hazard_pc = 0x14 (a consumidora),
#                 hazard_cycle = 7 (sub buscado no ciclo 6, em ID no ciclo 7).
# ------------------------------------------------------------------------
addi $t0, $zero, 5         # 0x00: $t0 = 5
addi $zero, $zero, 1       # 0x04: escrita em $zero (descartada)
add  $t1, $zero, $zero     # 0x08: lê $zero logo após 0x04 -> sem conflito
add  $t2, $t0, $t0         # 0x0c: lê $t0 a distância 3 -> sem conflito ($t2 = 10)
addi $t3, $zero, 3         # 0x10: produtora ($t3 = 3)
sub  $t4, $t3, $t2         # 0x14: consumidora a distância 1 -> CONFLITO DE DADOS
break                      # 0x18 (não é alcançado em O2)
