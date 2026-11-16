.text
# -------------------------------------------------------------------------
# Bloco A: Inicialização de constantes (addi)
# Usando $t0-$t7. Como todos leem de $zero, são independentes.
# -------------------------------------------------------------------------
addi $t0, $zero, 10      # $t0 = 10
addi $t1, $zero, 20      # $t1 = 20
addi $t2, $zero, 30      # $t2 = 30
addi $t3, $zero, 40      # $t3 = 40
addi $t4, $zero, 50      # $t4 = 50
addi $t5, $zero, 60      # $t5 = 60
addi $t6, $zero, 70      # $t6 = 70
addi $t7, $zero, 80      # $t7 = 80

# -------------------------------------------------------------------------
# Bloco B: Aritmética e Lógica (add, sub, and, or, slt)
# Produzindo resultados em $s0-$s7.
# -------------------------------------------------------------------------
add $s0, $t0, $t1        # $s0 = 30
sub $s1, $t2, $t3        # $s1 = -10
and $s2, $t4, $t5        # $s2 = 48
or  $s3, $t6, $t7        # $s3 = 86
slt $s4, $t0, $t2        # $s4 = 1 (10 < 30)
add $s5, $t1, $t3        # $s5 = 60
sub $s6, $t4, $t6        # $s6 = -20
and $s7, $t2, $t5        # $s7 = 28

# -------------------------------------------------------------------------
# Bloco C: Reutilização de registradores para manter distância
# -------------------------------------------------------------------------
addi $a0, $zero, 0      # $a0 = 0 (Base para memória)
add $t0, $s0, $s1        # $t0 = 20
sub $t1, $s2, $s3        # $t1 = -38
and $t2, $s4, $s5        # $t2 = 0
or  $t3, $s6, $s7        # $t3 = -4 (0xFFFFFFFC: -20 | 28)
slt $t4, $s0, $s5        # $t4 = 1 (30 < 60)

# -------------------------------------------------------------------------
# Bloco D: Memória (sw, lw)
# A distância entre o cálculo de $a0 e seu uso em sw é >= 3.
# A distância entre a produção de $s0-$s7 e seu consumo em lw é >> 3.
# -------------------------------------------------------------------------
sw $s0, 0($a0)           # Mem[0] = 30
sw $s1, 4($a0)           # Mem[4] = -10
sw $s2, 8($a0)           # Mem[8] = 48
sw $s3, 12($a0)          # Mem[12] = 86
lw $s4, 0($a0)           # $s4 = 30
lw $s5, 4($a0)           # $s5 = -10
lw $s6, 8($a0)           # $s6 = 48
lw $s7, 12($a0)          # $s7 = 86

# -------------------------------------------------------------------------
# Bloco E: Controle (beq)
# Todos os beq são NÃO TOMADOS para evitar conflitos de controle.
# A distância dos produtores ($s0, $s1, $s2, $s3) é >> 3.
# -------------------------------------------------------------------------
beq $s0, $s1, skip_beq_1 # 30 != -10 (Não tomado)
skip_beq_1:
beq $s2, $s3, skip_beq_2 # 48 != 86 (Não tomado)
skip_beq_2:

break                    # Fim do programa
