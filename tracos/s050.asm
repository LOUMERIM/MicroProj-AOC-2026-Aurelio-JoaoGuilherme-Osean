.text
# S050 — série S (R5): 50 instruções úteis, sem conflitos.
# Gerado por scripts/gerar_serie_s.py a partir de tracos/t0.asm (32 instruções úteis por cópia; 2 cópia(s), a última truncada se preciso).
# Não editar à mão: rode o script de novo.
addi $t0, $zero, 10             # 0x000
addi $t1, $zero, 20             # 0x004
addi $t2, $zero, 30             # 0x008
addi $t3, $zero, 40             # 0x00C
addi $t4, $zero, 50             # 0x010
addi $t5, $zero, 60             # 0x014
addi $t6, $zero, 70             # 0x018
addi $t7, $zero, 80             # 0x01C
add $s0, $t0, $t1               # 0x020
sub $s1, $t2, $t3               # 0x024
and $s2, $t4, $t5               # 0x028
or $s3, $t6, $t7                # 0x02C
slt $s4, $t0, $t2               # 0x030
add $s5, $t1, $t3               # 0x034
sub $s6, $t4, $t6               # 0x038
and $s7, $t2, $t5               # 0x03C
addi $a0, $zero, 0              # 0x040
add $t0, $s0, $s1               # 0x044
sub $t1, $s2, $s3               # 0x048
and $t2, $s4, $s5               # 0x04C
or $t3, $s6, $s7                # 0x050
slt $t4, $s0, $s5               # 0x054
sw $s0, 0($a0)                  # 0x058
sw $s1, 4($a0)                  # 0x05C
sw $s2, 8($a0)                  # 0x060
sw $s3, 12($a0)                 # 0x064
lw $s4, 0($a0)                  # 0x068
lw $s5, 4($a0)                  # 0x06C
lw $s6, 8($a0)                  # 0x070
lw $s7, 12($a0)                 # 0x074
beq $s0, $s1, skip_beq_1_c1     # 0x078
skip_beq_1_c1:
beq $s2, $s3, skip_beq_2_c1     # 0x07C
skip_beq_2_c1:
addi $t0, $zero, 10             # 0x080
addi $t1, $zero, 20             # 0x084
addi $t2, $zero, 30             # 0x088
addi $t3, $zero, 40             # 0x08C
addi $t4, $zero, 50             # 0x090
addi $t5, $zero, 60             # 0x094
addi $t6, $zero, 70             # 0x098
addi $t7, $zero, 80             # 0x09C
add $s0, $t0, $t1               # 0x0A0
sub $s1, $t2, $t3               # 0x0A4
and $s2, $t4, $t5               # 0x0A8
or $s3, $t6, $t7                # 0x0AC
slt $s4, $t0, $t2               # 0x0B0
add $s5, $t1, $t3               # 0x0B4
sub $s6, $t4, $t6               # 0x0B8
and $s7, $t2, $t5               # 0x0BC
addi $a0, $zero, 0              # 0x0C0
add $t0, $s0, $s1               # 0x0C4
break                           # 0x0C8 fim (não conta no CPI)
