.text
# S020 — série S (R5): 20 instruções úteis, sem conflitos.
# Gerado por scripts/gerar_serie_s.py a partir de tracos/t0.asm (32 instruções úteis por cópia; 1 cópia(s), a última truncada se preciso).
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
break                           # 0x050 fim (não conta no CPI)
