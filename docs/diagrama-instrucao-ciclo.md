# Diagramas instrução × ciclo do T0 (issue #22)

Gerados de `t0.asm` simulado na O1 e na O2 (`make diagramas`), no formato da seção 6.1 do enunciado: cada linha é uma instrução, cada coluna um ciclo e a célula mostra o estágio. Ciclo 1 = primeiro ciclo após o reset (convenção do `tb_cpu`). Nada é escrito à mão: o script lê os dumps GHW e confere que cada instrução percorre os estágios em ordem.

- **O1 (multiciclo):** o estágio vem do estado da FSM (`FETCH` = IF, `DECODE` = ID, `*_EXEC`/`ADDR`/`BRANCH` = EX, `MEM_READ`/`MEM_WRITE` = MEM, `*_WB` = WB). Uma instrução por vez; o T0 inteiro leva 133 ciclos. `HALT` é o ciclo em que `done = 1`, depois do `break`.
- **O2 (pipeline):** o estágio vem do PC presente em IF e nos registradores IF/ID, ID/EX, EX/MEM e MEM/WB. Uma instrução entra por ciclo; o T0 inteiro leva 37 ciclos e o `break` conclui em WB no C37 (`done = 1`).

As 3 últimas instruções do T0 são os dois `beq` (não tomados) e o `break`.

## O1 — multiciclo

#### 10 primeiras instruções

| Instrução | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | C10 | C11 | C12 | C13 | C14 | C15 | C16 | C17 | C18 | C19 | C20 | C21 | C22 | C23 | C24 | C25 | C26 | C27 | C28 | C29 | C30 | C31 | C32 | C33 | C34 | C35 | C36 | C37 | C38 | C39 | C40 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0x00` addi $t0, $zero, 10 | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x04` addi $t1, $zero, 20 |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x08` addi $t2, $zero, 30 |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x0C` addi $t3, $zero, 40 |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x10` addi $t4, $zero, 50 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x14` addi $t5, $zero, 60 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x18` addi $t6, $zero, 70 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |  |  |  |  |
| `0x1C` addi $t7, $zero, 80 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |  |  |  |  |
| `0x20` add $s0, $t0, $t1 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |  |  |  |  |
| `0x24` sub $s1, $t2, $t3 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF | ID | EX | WB |

#### 3 últimas instruções

| Instrução | C125 | C126 | C127 | C128 | C129 | C130 | C131 | C132 | C133 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0x78` beq $s0, $s1, skip_beq_1 | IF | ID | EX |  |  |  |  |  |  |
| `0x7C` beq $s2, $s3, skip_beq_2 |  |  |  | IF | ID | EX |  |  |  |
| `0x80` break |  |  |  |  |  |  | IF | ID | HALT |

## O2 — pipeline de 5 estágios

#### 10 primeiras instruções

| Instrução | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | C10 | C11 | C12 | C13 | C14 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0x00` addi $t0, $zero, 10 | IF | ID | EX | MEM | WB |  |  |  |  |  |  |  |  |  |
| `0x04` addi $t1, $zero, 20 |  | IF | ID | EX | MEM | WB |  |  |  |  |  |  |  |  |
| `0x08` addi $t2, $zero, 30 |  |  | IF | ID | EX | MEM | WB |  |  |  |  |  |  |  |
| `0x0C` addi $t3, $zero, 40 |  |  |  | IF | ID | EX | MEM | WB |  |  |  |  |  |  |
| `0x10` addi $t4, $zero, 50 |  |  |  |  | IF | ID | EX | MEM | WB |  |  |  |  |  |
| `0x14` addi $t5, $zero, 60 |  |  |  |  |  | IF | ID | EX | MEM | WB |  |  |  |  |
| `0x18` addi $t6, $zero, 70 |  |  |  |  |  |  | IF | ID | EX | MEM | WB |  |  |  |
| `0x1C` addi $t7, $zero, 80 |  |  |  |  |  |  |  | IF | ID | EX | MEM | WB |  |  |
| `0x20` add $s0, $t0, $t1 |  |  |  |  |  |  |  |  | IF | ID | EX | MEM | WB |  |
| `0x24` sub $s1, $t2, $t3 |  |  |  |  |  |  |  |  |  | IF | ID | EX | MEM | WB |

#### 3 últimas instruções

| Instrução | C31 | C32 | C33 | C34 | C35 | C36 | C37 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `0x78` beq $s0, $s1, skip_beq_1 | IF | ID | EX | MEM | WB |  |  |
| `0x7C` beq $s2, $s3, skip_beq_2 |  | IF | ID | EX | MEM | WB |  |
| `0x80` break |  |  | IF | ID | EX | MEM | WB |

## Tabelas completas

Todas as instruções e todos os ciclos: `docs/diagramas/t0_o1_instr_ciclo.csv` e `docs/diagramas/t0_o2_instr_ciclo.csv` (abrem em planilha, separador `;`).
