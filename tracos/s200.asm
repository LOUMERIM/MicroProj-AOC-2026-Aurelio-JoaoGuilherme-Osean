.text
# S200 — série S (R5): 200 instruções úteis, sem conflitos.
# Gerado por scripts/gerar_serie_s.py a partir de tracos/t0.asm (32 instruções úteis por cópia; 7 cópia(s), a última truncada se preciso).
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
sub $t1, $s2, $s3               # 0x0C8
and $t2, $s4, $s5               # 0x0CC
or $t3, $s6, $s7                # 0x0D0
slt $t4, $s0, $s5               # 0x0D4
sw $s0, 0($a0)                  # 0x0D8
sw $s1, 4($a0)                  # 0x0DC
sw $s2, 8($a0)                  # 0x0E0
sw $s3, 12($a0)                 # 0x0E4
lw $s4, 0($a0)                  # 0x0E8
lw $s5, 4($a0)                  # 0x0EC
lw $s6, 8($a0)                  # 0x0F0
lw $s7, 12($a0)                 # 0x0F4
beq $s0, $s1, skip_beq_1_c2     # 0x0F8
skip_beq_1_c2:
beq $s2, $s3, skip_beq_2_c2     # 0x0FC
skip_beq_2_c2:
addi $t0, $zero, 10             # 0x100
addi $t1, $zero, 20             # 0x104
addi $t2, $zero, 30             # 0x108
addi $t3, $zero, 40             # 0x10C
addi $t4, $zero, 50             # 0x110
addi $t5, $zero, 60             # 0x114
addi $t6, $zero, 70             # 0x118
addi $t7, $zero, 80             # 0x11C
add $s0, $t0, $t1               # 0x120
sub $s1, $t2, $t3               # 0x124
and $s2, $t4, $t5               # 0x128
or $s3, $t6, $t7                # 0x12C
slt $s4, $t0, $t2               # 0x130
add $s5, $t1, $t3               # 0x134
sub $s6, $t4, $t6               # 0x138
and $s7, $t2, $t5               # 0x13C
addi $a0, $zero, 0              # 0x140
add $t0, $s0, $s1               # 0x144
sub $t1, $s2, $s3               # 0x148
and $t2, $s4, $s5               # 0x14C
or $t3, $s6, $s7                # 0x150
slt $t4, $s0, $s5               # 0x154
sw $s0, 0($a0)                  # 0x158
sw $s1, 4($a0)                  # 0x15C
sw $s2, 8($a0)                  # 0x160
sw $s3, 12($a0)                 # 0x164
lw $s4, 0($a0)                  # 0x168
lw $s5, 4($a0)                  # 0x16C
lw $s6, 8($a0)                  # 0x170
lw $s7, 12($a0)                 # 0x174
beq $s0, $s1, skip_beq_1_c3     # 0x178
skip_beq_1_c3:
beq $s2, $s3, skip_beq_2_c3     # 0x17C
skip_beq_2_c3:
addi $t0, $zero, 10             # 0x180
addi $t1, $zero, 20             # 0x184
addi $t2, $zero, 30             # 0x188
addi $t3, $zero, 40             # 0x18C
addi $t4, $zero, 50             # 0x190
addi $t5, $zero, 60             # 0x194
addi $t6, $zero, 70             # 0x198
addi $t7, $zero, 80             # 0x19C
add $s0, $t0, $t1               # 0x1A0
sub $s1, $t2, $t3               # 0x1A4
and $s2, $t4, $t5               # 0x1A8
or $s3, $t6, $t7                # 0x1AC
slt $s4, $t0, $t2               # 0x1B0
add $s5, $t1, $t3               # 0x1B4
sub $s6, $t4, $t6               # 0x1B8
and $s7, $t2, $t5               # 0x1BC
addi $a0, $zero, 0              # 0x1C0
add $t0, $s0, $s1               # 0x1C4
sub $t1, $s2, $s3               # 0x1C8
and $t2, $s4, $s5               # 0x1CC
or $t3, $s6, $s7                # 0x1D0
slt $t4, $s0, $s5               # 0x1D4
sw $s0, 0($a0)                  # 0x1D8
sw $s1, 4($a0)                  # 0x1DC
sw $s2, 8($a0)                  # 0x1E0
sw $s3, 12($a0)                 # 0x1E4
lw $s4, 0($a0)                  # 0x1E8
lw $s5, 4($a0)                  # 0x1EC
lw $s6, 8($a0)                  # 0x1F0
lw $s7, 12($a0)                 # 0x1F4
beq $s0, $s1, skip_beq_1_c4     # 0x1F8
skip_beq_1_c4:
beq $s2, $s3, skip_beq_2_c4     # 0x1FC
skip_beq_2_c4:
addi $t0, $zero, 10             # 0x200
addi $t1, $zero, 20             # 0x204
addi $t2, $zero, 30             # 0x208
addi $t3, $zero, 40             # 0x20C
addi $t4, $zero, 50             # 0x210
addi $t5, $zero, 60             # 0x214
addi $t6, $zero, 70             # 0x218
addi $t7, $zero, 80             # 0x21C
add $s0, $t0, $t1               # 0x220
sub $s1, $t2, $t3               # 0x224
and $s2, $t4, $t5               # 0x228
or $s3, $t6, $t7                # 0x22C
slt $s4, $t0, $t2               # 0x230
add $s5, $t1, $t3               # 0x234
sub $s6, $t4, $t6               # 0x238
and $s7, $t2, $t5               # 0x23C
addi $a0, $zero, 0              # 0x240
add $t0, $s0, $s1               # 0x244
sub $t1, $s2, $s3               # 0x248
and $t2, $s4, $s5               # 0x24C
or $t3, $s6, $s7                # 0x250
slt $t4, $s0, $s5               # 0x254
sw $s0, 0($a0)                  # 0x258
sw $s1, 4($a0)                  # 0x25C
sw $s2, 8($a0)                  # 0x260
sw $s3, 12($a0)                 # 0x264
lw $s4, 0($a0)                  # 0x268
lw $s5, 4($a0)                  # 0x26C
lw $s6, 8($a0)                  # 0x270
lw $s7, 12($a0)                 # 0x274
beq $s0, $s1, skip_beq_1_c5     # 0x278
skip_beq_1_c5:
beq $s2, $s3, skip_beq_2_c5     # 0x27C
skip_beq_2_c5:
addi $t0, $zero, 10             # 0x280
addi $t1, $zero, 20             # 0x284
addi $t2, $zero, 30             # 0x288
addi $t3, $zero, 40             # 0x28C
addi $t4, $zero, 50             # 0x290
addi $t5, $zero, 60             # 0x294
addi $t6, $zero, 70             # 0x298
addi $t7, $zero, 80             # 0x29C
add $s0, $t0, $t1               # 0x2A0
sub $s1, $t2, $t3               # 0x2A4
and $s2, $t4, $t5               # 0x2A8
or $s3, $t6, $t7                # 0x2AC
slt $s4, $t0, $t2               # 0x2B0
add $s5, $t1, $t3               # 0x2B4
sub $s6, $t4, $t6               # 0x2B8
and $s7, $t2, $t5               # 0x2BC
addi $a0, $zero, 0              # 0x2C0
add $t0, $s0, $s1               # 0x2C4
sub $t1, $s2, $s3               # 0x2C8
and $t2, $s4, $s5               # 0x2CC
or $t3, $s6, $s7                # 0x2D0
slt $t4, $s0, $s5               # 0x2D4
sw $s0, 0($a0)                  # 0x2D8
sw $s1, 4($a0)                  # 0x2DC
sw $s2, 8($a0)                  # 0x2E0
sw $s3, 12($a0)                 # 0x2E4
lw $s4, 0($a0)                  # 0x2E8
lw $s5, 4($a0)                  # 0x2EC
lw $s6, 8($a0)                  # 0x2F0
lw $s7, 12($a0)                 # 0x2F4
beq $s0, $s1, skip_beq_1_c6     # 0x2F8
skip_beq_1_c6:
beq $s2, $s3, skip_beq_2_c6     # 0x2FC
skip_beq_2_c6:
addi $t0, $zero, 10             # 0x300
addi $t1, $zero, 20             # 0x304
addi $t2, $zero, 30             # 0x308
addi $t3, $zero, 40             # 0x30C
addi $t4, $zero, 50             # 0x310
addi $t5, $zero, 60             # 0x314
addi $t6, $zero, 70             # 0x318
addi $t7, $zero, 80             # 0x31C
break                           # 0x320 fim (não conta no CPI)
