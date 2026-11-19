# Traço T0: endereços, registradores e distâncias (seção 6 do enunciado)

Gerada por `scripts/tabela_t0.py` a partir de `t0.asm` (`make tabela-t0`). Nada é digitado à mão.

- **Lê / Escreve:** registradores usados pela instrução. Leituras de `$zero` e escritas em `$zero` não geram dependência (R1).
- **Produtor mais próximo:** a instrução anterior que escreveu o registrador lido há menos tempo, e por qual registrador.
- **Distância:** 1 = instrução imediatamente anterior. Na O2 as distâncias **1 e 2 são conflito de dados**; a distância 3 não é (o banco escreve na 1ª metade do ciclo e lê na 2ª).
- `—` em Produtor/Distância: a instrução só lê `$zero` ou nenhum registrador (inclui o `break`).

| # | Endereço | Instrução | Lê | Escreve | Produtor mais próximo | Distância |
| ---: | :---: | --- | --- | :---: | --- | :---: |
| 1 | `0x00` | `addi $t0, $zero, 10` | — | $t0 | — | — |
| 2 | `0x04` | `addi $t1, $zero, 20` | — | $t1 | — | — |
| 3 | `0x08` | `addi $t2, $zero, 30` | — | $t2 | — | — |
| 4 | `0x0C` | `addi $t3, $zero, 40` | — | $t3 | — | — |
| 5 | `0x10` | `addi $t4, $zero, 50` | — | $t4 | — | — |
| 6 | `0x14` | `addi $t5, $zero, 60` | — | $t5 | — | — |
| 7 | `0x18` | `addi $t6, $zero, 70` | — | $t6 | — | — |
| 8 | `0x1C` | `addi $t7, $zero, 80` | — | $t7 | — | — |
| 9 | `0x20` | `add $s0, $t0, $t1` | $t0, $t1 | $s0 | `0x04` addi $t1, $zero, 20 (via $t1) | 7 |
| 10 | `0x24` | `sub $s1, $t2, $t3` | $t2, $t3 | $s1 | `0x0C` addi $t3, $zero, 40 (via $t3) | 6 |
| 11 | `0x28` | `and $s2, $t4, $t5` | $t4, $t5 | $s2 | `0x14` addi $t5, $zero, 60 (via $t5) | 5 |
| 12 | `0x2C` | `or $s3, $t6, $t7` | $t6, $t7 | $s3 | `0x1C` addi $t7, $zero, 80 (via $t7) | 4 |
| 13 | `0x30` | `slt $s4, $t0, $t2` | $t0, $t2 | $s4 | `0x08` addi $t2, $zero, 30 (via $t2) | 10 |
| 14 | `0x34` | `add $s5, $t1, $t3` | $t1, $t3 | $s5 | `0x0C` addi $t3, $zero, 40 (via $t3) | 10 |
| 15 | `0x38` | `sub $s6, $t4, $t6` | $t4, $t6 | $s6 | `0x18` addi $t6, $zero, 70 (via $t6) | 8 |
| 16 | `0x3C` | `and $s7, $t2, $t5` | $t2, $t5 | $s7 | `0x14` addi $t5, $zero, 60 (via $t5) | 10 |
| 17 | `0x40` | `addi $a0, $zero, 0` | — | $a0 | — | — |
| 18 | `0x44` | `add $t0, $s0, $s1` | $s0, $s1 | $t0 | `0x24` sub $s1, $t2, $t3 (via $s1) | 8 |
| 19 | `0x48` | `sub $t1, $s2, $s3` | $s2, $s3 | $t1 | `0x2C` or $s3, $t6, $t7 (via $s3) | 7 |
| 20 | `0x4C` | `and $t2, $s4, $s5` | $s4, $s5 | $t2 | `0x34` add $s5, $t1, $t3 (via $s5) | 6 |
| 21 | `0x50` | `or $t3, $s6, $s7` | $s6, $s7 | $t3 | `0x3C` and $s7, $t2, $t5 (via $s7) | 5 |
| 22 | `0x54` | `slt $t4, $s0, $s5` | $s0, $s5 | $t4 | `0x34` add $s5, $t1, $t3 (via $s5) | 8 |
| 23 | `0x58` | `sw $s0, 0($a0)` | $a0, $s0 | — | `0x40` addi $a0, $zero, 0 (via $a0) | 6 |
| 24 | `0x5C` | `sw $s1, 4($a0)` | $a0, $s1 | — | `0x40` addi $a0, $zero, 0 (via $a0) | 7 |
| 25 | `0x60` | `sw $s2, 8($a0)` | $a0, $s2 | — | `0x40` addi $a0, $zero, 0 (via $a0) | 8 |
| 26 | `0x64` | `sw $s3, 12($a0)` | $a0, $s3 | — | `0x40` addi $a0, $zero, 0 (via $a0) | 9 |
| 27 | `0x68` | `lw $s4, 0($a0)` | $a0 | $s4 | `0x40` addi $a0, $zero, 0 (via $a0) | 10 |
| 28 | `0x6C` | `lw $s5, 4($a0)` | $a0 | $s5 | `0x40` addi $a0, $zero, 0 (via $a0) | 11 |
| 29 | `0x70` | `lw $s6, 8($a0)` | $a0 | $s6 | `0x40` addi $a0, $zero, 0 (via $a0) | 12 |
| 30 | `0x74` | `lw $s7, 12($a0)` | $a0 | $s7 | `0x40` addi $a0, $zero, 0 (via $a0) | 13 |
| 31 | `0x78` | `beq $s0, $s1, skip_beq_1` | $s0, $s1 | — | `0x24` sub $s1, $t2, $t3 (via $s1) | 21 |
| 32 | `0x7C` | `beq $s2, $s3, skip_beq_2` | $s2, $s3 | — | `0x2C` or $s3, $t6, $t7 (via $s3) | 20 |
| 33 | `0x80` | `break` | — | — | — | — |

**Resumo:** 33 instruções (32 úteis + `break`); 23 têm dependência de dados e **a menor distância é 4**, ou seja, nenhuma está a distância 1 ou 2: o T0 não tem conflito de dados na O2. O mesmo vale para a O1, que não tem conflitos.
