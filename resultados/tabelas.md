# Tabelas de resultados

Geradas por `scripts/run_all.sh` a partir de `metricas.csv` e `resultados/conflitos.csv`. Ciclos contados do 1º ciclo após o reset até `done = 1`, inclusive; o `break` não entra em instruções, CPI e IPC.

## T0 por organização

| Organização | Ciclos | Instruções | CPI | IPC | Ocupação | Período (ns) | Tempo (ns) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| O1 | 133 | 32 | 4,156 | 0,241 | 98,5 % | 0,22 | 29,260 |
| O2 | 37 | 32 | 1,156 | 0,865 | 89,2 % | 0,22 | 8,140 |

## Speedup da O2 sobre a O1

| Traço | Instruções | Ciclos O1 | Ciclos O2 | Speedup em ciclos (O1/O2) | Tempo O1 (ns) | Tempo O2 (ns) | Speedup em tempo | Speedup ideal (5 estágios) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T0 | 32 | 133 | 37 | 3,595 | 29,260 | 8,140 | 3,595 | 5 |
| S005 | 5 | 23 | 10 | 2,300 | 5,060 | 2,200 | 2,300 | 5 |
| S010 | 10 | 43 | 15 | 2,867 | 9,460 | 3,300 | 2,867 | 5 |
| S020 | 20 | 83 | 25 | 3,320 | 18,260 | 5,500 | 3,320 | 5 |
| S050 | 50 | 205 | 55 | 3,727 | 45,100 | 12,100 | 3,727 | 5 |
| S100 | 100 | 409 | 105 | 3,895 | 89,980 | 23,100 | 3,895 | 5 |
| S200 | 200 | 815 | 205 | 3,976 | 179,300 | 45,100 | 3,976 | 5 |

Períodos de clock: O1 = 0,22 ns, O2 = 0,22 ns (critério e justificativa em `docs/periodo-clock.md`).

## Série S: efeito do enchimento e do esvaziamento

| Traço | Instruções | Ciclos O1 | Ciclos O2 | CPI O1 | CPI O2 | Ciclos O2 − instruções | Ocupação O2 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S005 | 5 | 23 | 10 | 4,600 | 2,000 | 5 | 60,0 % |
| S010 | 10 | 43 | 15 | 4,300 | 1,500 | 5 | 73,3 % |
| S020 | 20 | 83 | 25 | 4,150 | 1,250 | 5 | 84,0 % |
| S050 | 50 | 205 | 55 | 4,100 | 1,100 | 5 | 92,7 % |
| S100 | 100 | 409 | 105 | 4,090 | 1,050 | 5 | 96,2 % |
| S200 | 200 | 815 | 205 | 4,075 | 1,025 | 5 | 98,0 % |

## Ocupação por estágio e por via (O2)

| Traço | IF | ID | EX | MEM | WB | Via 0 | Via 1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T0 | 89,2 % | 89,2 % | 89,2 % | 89,2 % | 89,2 % | 89,2 % | — |
| S005 | 60,0 % | 60,0 % | 60,0 % | 60,0 % | 60,0 % | 60,0 % | — |
| S010 | 73,3 % | 73,3 % | 73,3 % | 73,3 % | 73,3 % | 73,3 % | — |
| S020 | 84,0 % | 84,0 % | 84,0 % | 84,0 % | 84,0 % | 84,0 % | — |
| S050 | 92,7 % | 92,7 % | 92,7 % | 92,7 % | 92,7 % | 92,7 % | — |
| S100 | 96,2 % | 96,2 % | 96,2 % | 96,2 % | 96,2 % | 96,2 % | — |
| S200 | 98,0 % | 98,0 % | 98,0 % | 98,0 % | 98,0 % | 98,0 % | — |

Na O1 só existe o slot 0 (`stage_valid(0)`): T0 98,5 %, S005 91,3 %, S010 95,3 %, S020 97,6 %, S050 99,0 %, S100 99,5 %, S200 99,8 %.

## Registro de conflitos

| Traço | Organização | Tipo esperado | Tipo detectado | hazard_pc | hazard_cycle | Resultado |
| --- | --- | --- | --- | --- | --- | --- |
| TD | O2 | 01 (dados) | 01 (dados) | 0x00000014 | 7 | ok |
| TE | O2 | 10 (estrutural) | 10 (estrutural) | 0x00000018 | 7 | ok |
| TC | O2 | 11 (controle) | 11 (controle) | 0x00000018 | 9 | ok |

Na O1 os traços TD, TE, TC executam até o fim sem conflito e conferem o esperado.
