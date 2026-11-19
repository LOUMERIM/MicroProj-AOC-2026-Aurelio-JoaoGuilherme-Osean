.text
# S005 — série S (R5): 5 instruções úteis, sem conflitos.
# Gerado por scripts/gerar_serie_s.py a partir de tracos/t0.asm (32 instruções úteis por cópia; 1 cópia(s), a última truncada se preciso).
# Não editar à mão: rode o script de novo.
addi $t0, $zero, 10             # 0x000
addi $t1, $zero, 20             # 0x004
addi $t2, $zero, 30             # 0x008
addi $t3, $zero, 40             # 0x00C
addi $t4, $zero, 50             # 0x010
break                           # 0x014 fim (não conta no CPI)
