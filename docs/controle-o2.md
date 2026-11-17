# Conflito de controle na O2 (issue #14)

## Estágio de resolução do desvio: EX

Na O2 o `beq` é resolvido no estágio **EX**: a ULA calcula `rs - rt` e o sinal
`zero` decide se o desvio é tomado; o somador do alvo (`PC + 4 + (imm << 2)`)
também fica em EX, alimentado por `ID/EX.pc_plus4` e `ID/EX.imm`.

### Por que EX, e não ID ou MEM

| Estágio | Instruções já buscadas quando o desvio se resolve | Hardware extra | Efeito no período de clock |
| --- | --- | --- | --- |
| ID | 1 (em IF) | comparador de 32 bits e somador de alvo em ID | ID passa a ser leitura do banco + comparação: caminho crítico maior |
| **EX** | **2 (em ID e IF)** | **nenhum: reaproveita a ULA (`SUB` + `zero`) e o somador de alvo** | **inalterado** |
| MEM | 3 (em EX, ID e IF) | nenhum | inalterado, mas há mais instruções no caminho errado |

- **Contra ID:** a O2 não tem forwarding. Comparar em ID exigiria um
  comparador dedicado logo depois da leitura assíncrona do banco, que já ocupa a
  2ª metade do ciclo (R2). Isso alonga o estágio ID e, com o mesmo critério de
  período nas duas organizações (R6), pioraria o clock da O2 inteira.
- **Contra MEM:** não há ganho de hardware em esperar mais um estágio; só aumenta
  o número de instruções buscadas no caminho errado.
- **A favor de EX:** os operandos do `beq` (`rs_value`, `rt_value`) já estão em
  `ID/EX`, a ULA já sabe fazer `SUB` e gera `zero`, e as regras de distância do
  conflito de dados (issue #12) continuam valendo para o `beq` como para qualquer
  instrução que lê `rs` e `rt` em ID.

## Detecção

```
branch_taken     = ID/EX.valid and ID/EX.is_beq and alu_zero
control_conflict = branch_taken and (IF/ID.valid or IF real) and not frozen
```

- **beq tomado:** quando ele está em EX, a instrução seguinte já está em ID e a
  próxima está sendo buscada em IF. Sem flush, as duas seriam executadas; então o
  processador **aborta** no próprio ciclo: `hazard_type = 11`,
  `hazard_pc = PC do beq` (`ID/EX.pc_plus4 - 4`), `hazard_cycle` = ciclo em que o
  beq está em EX.
- **beq não tomado:** buscar em sequência é exatamente o caminho correto, então
  **não é conflito** e a execução segue.
- **Aborto (R4/issue #15):** o PC e os registradores entre estágios não avançam;
  as instruções do caminho errado (ID e IF) nunca produzem efeito. As mais
  antigas, em MEM e WB, concluem o que já tinham iniciado.
- **Prioridade:** se mais de um conflito acontecer no mesmo ciclo, vale o da
  instrução mais antiga: controle (EX) > dados (ID) > estrutural (IF).

## Verificação: traço TC

`tracos/tc.asm` tem um `beq` não tomado em `0x10` (não pode abortar) e um `beq`
tomado em `0x18`, com `0x1c` e `0x20` já buscadas:

```bash
make sim ORG=O2 SLOTS=5 PROG=tracos/tc.hex ESPERADO=tracos/tc_esperado.txt ABORTO=true TIPO=3 PCESP=00000018
# O2: ABORTO tipo=11 pc=0x00000018 ciclo=9
make sim PROG=tracos/tc.hex ESPERADO=tracos/tc_esperado.txt   # O1 segue o desvio e confere os registradores
```
