.text
# S010 — série S (R5): 10 instruções úteis, sem conflitos.
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
break                           # 0x028 fim (não conta no CPI)
