# T0: 30 instrucoes uteis independentes; break nao conta como instrucao util.
# As stores e loads verificam o caminho de memoria usando os valores do banco.
addi $1,  $zero, 5
addi $2,  $zero, 3
add  $3,  $zero, $zero
sub  $4,  $zero, $zero
and  $5,  $zero, $zero
or   $6,  $zero, $zero
slt  $7,  $zero, $zero
addi $9,  $zero, -1
addi $10, $zero, 32767
addi $11, $zero, -32768
addi $12, $zero, 1
sw   $1,  0($zero)
lw   $13, 0($zero)
beq  $zero, $1, 0
addi $14, $zero, -1
sub  $15, $zero, $zero
and  $16, $zero, $zero
or   $17, $zero, $zero
slt  $18, $zero, $zero
sw   $2,  4($zero)
lw   $19, 4($zero)
beq  $zero, $1, 0
addi $20, $zero, 42
add  $21, $zero, $zero
addi $22, $zero, 10
addi $23, $zero, 7
sw   $zero, 8($zero)
lw   $24, 8($zero)
beq  $zero, $1, 0
addi $25, $zero, 99
break
