# Período de clock da O1 e da O2 (issue #21)

## Critério

O enunciado (R6) aceita síntese ou uma tabela de atrasos por componente, desde que o **mesmo
critério** seja usado nas duas organizações e que o overhead dos registradores entre estágios entre
na conta. Não há ferramenta de síntese no ambiente do projeto (GHDL + GTKWave), então adotamos a
**tabela de atrasos do livro** (Patterson & Hennessy, *Organização e Projeto de Computadores*, cap. 4,
tempos das unidades funcionais) e a aplicamos, ciclo a ciclo, ao que cada organização faz no seu RTL.

O período é o maior caminho entre dois registradores, mais o overhead do registrador:

    T = max(atraso do caminho em cada estado/estágio) + t_reg

### Tabela de atrasos adotada

| Unidade | Atraso | Onde aparece |
| --- | ---: | --- |
| Memória de instruções (leitura) | 200 ps | O1 `FETCH`; O2 IF |
| Memória de dados (leitura ou escrita) | 200 ps | O1 `MEM_READ`/`MEM_WRITE`; O2 MEM |
| ULA (inclui o somador de PC+4 e de alvo) | 200 ps | O1 `FETCH`, `DECODE`, `*_EXEC`, `ADDR`, `BRANCH`; O2 IF (PC+4), EX |
| Banco de registradores, leitura | 100 ps | O1 `DECODE`; O2 ID |
| Banco de registradores, escrita | 100 ps | O1 `*_WB`; O2 WB |
| Overhead de registrador (`t_reg` = clk→Q + setup) | 20 ps | toda fronteira de ciclo, nas duas |

Premissas, iguais às do livro e iguais nas duas organizações:

- multiplexadores, extensão de sinal, decodificação, lógica de controle e comparadores da unidade de
  detecção de conflitos têm atraso desprezível frente às unidades acima;
- o banco de registradores é o **mesmo componente** (`vhdl/register_file.vhd`) nas duas: escreve na
  borda de descida e lê de forma combinacional, isto é, **escreve na 1ª metade do ciclo e lê na 2ª**
  (R2). Por isso a escrita (100 ps) e a leitura (100 ps) têm de caber, cada uma, em meio período:
  `T/2 ≥ 100 ps`;
- `t_reg` = 20 ps é um valor **adotado pelo trio** (o livro não fixa um valor único). Como ele é
  somado igualmente nas duas organizações, a escolha **não altera a comparação** entre elas (ver
  abaixo).

## O1 — multiciclo

Um estado por ciclo (`docs/fsm-o1.md`). Caminho mais longo de cada estado, entre registradores
(`PC`, `IR`, `A`, `B`, `ALUOut`, `MDR`):

| Estado | O que acontece no ciclo | Caminho crítico |
| --- | --- | ---: |
| `FETCH` | `IR ← IMem[PC]` em paralelo com `PC ← PC + 4` (ULA) | max(200, 200) = 200 ps |
| `DECODE` | `A, B ← Reg` em paralelo com `ALUOut ← PC + (imm<<2)` | max(100, 200) = 200 ps |
| `R_EXEC`, `ADDI_EXEC`, `ADDR` | `ALUOut ← ULA(A, B/imm)` | 200 ps |
| `BRANCH` | ULA `A − B`, `zero` decide a escrita do PC | 200 ps |
| `MEM_READ`, `MEM_WRITE` | acesso à memória de dados | 200 ps |
| `R_WB`, `ADDI_WB`, `MEM_WB` | escrita no banco (meio ciclo) | 100 ps ≤ T/2 → T ≥ 200 ps |

**T(O1) = 200 + 20 = 220 ps**

## O2 — pipeline de 5 estágios

Um estágio por ciclo, entre os registradores IF/ID, ID/EX, EX/MEM e MEM/WB:

| Estágio | O que acontece no ciclo | Caminho crítico |
| --- | --- | ---: |
| IF | `IMem[PC]` em paralelo com `PC + 4` | max(200, 200) = 200 ps |
| ID | escrita de WB na 1ª metade + leitura de `rs`/`rt` na 2ª; decodificação e detecção de conflito de dados em paralelo | 100 + 100 = 200 ps |
| EX | ULA (operando B escolhido por mux); somador de alvo em paralelo; `zero` → detecção de conflito de controle | 200 ps |
| MEM | acesso à memória de dados | 200 ps |
| WB | escrita no banco (1ª metade do ciclo, contada em ID) | 100 ps ≤ T/2 |

**T(O2) = 200 + 20 = 220 ps**

## Resultado e consequência para as métricas

| Organização | Maior caminho | t_reg | Período | Frequência |
| --- | ---: | ---: | ---: | ---: |
| O1 | 200 ps | 20 ps | **220 ps** | ≈ 4,55 GHz |
| O2 | 200 ps | 20 ps | **220 ps** | ≈ 4,55 GHz |

Os dois períodos são iguais porque, com o mesmo critério, as duas organizações são limitadas pela
mesma unidade mais lenta (memória/ULA, 200 ps) e pagam o mesmo overhead por ciclo: a O1 já divide a
instrução em estados de uma unidade funcional cada, exatamente como os estágios da O2. Consequências:

- o **speedup em tempo** da O2 sobre a O1 é igual ao **speedup em ciclos** (ciclos O1 / ciclos O2),
  para qualquer valor de `t_reg`;
- o tempo de execução é `ciclos × 0,22 ns` nas duas (T0: O1 = 133 × 0,22 = 29,26 ns; O2 = 37 × 0,22 =
  8,14 ns).

O `scripts/run_all.sh` usa esses períodos por padrão (`PERIODO_O1_NS=0.22`, `PERIODO_O2_NS=0.22`);
para outro critério, basta passar outros valores pelas mesmas variáveis.

**Limitação:** os valores são de livro, não de síntese, e desprezam muxes e lógica de controle. Se
algum dia houver síntese (Yosys/Quartus/Vivado), ela deve ser rodada nas duas organizações com a
mesma tecnologia, e os períodos medidos substituem os desta tabela.
