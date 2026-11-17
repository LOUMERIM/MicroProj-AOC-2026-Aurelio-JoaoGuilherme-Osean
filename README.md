# MicroProj-AOC — Aurelio, João Guilherme e Osean

Microprojeto de Arquitetura e Organização de Computadores (2026): processador MIPS
(subconjunto mínimo da ISA) descrito em **VHDL-2008**, simulado com **GHDL** e
inspecionado no **GTKWave**.

- **O1** — organização multiciclo.
- **O2** — organização em pipeline, com detecção de conflitos (dados, estrutural e controle).

As instruções suportadas estão em [`isa_table_mips.md`](isa_table_mips.md).

## Documentação da O1

- [FSM, caminho de dados e ISA da O1](docs/fsm-o1.md): premissas, diagrama do datapath com registradores e muxes, estados, sinais de controle e ciclos por classe.
- [Conflito de controle na O2](docs/controle-o2.md): por que o `beq` é resolvido em EX e como o desvio tomado é detectado.
- [Execução do T0 na O2](docs/waveform-t0-o2.md): waveform anotada (enchimento, pipeline cheio e esvaziamento), gerada por `make wave-t0`.
- [Período de clock](docs/periodo-clock.md): tabela de atrasos, caminho crítico por estado (O1) e por estágio (O2) e o período adotado (mesmo critério nas duas).

## Estrutura de pastas

```
.
├── docs/
│   ├── fsm-o1.md       # FSM, caminho de dados e ciclos por classe da O1
│   ├── controle-o2.md  # O2: estágio de resolução do beq (EX), justificativa e detecção
│   ├── waveform-t0-o2.md # O2: waveform anotada do T0 (enchimento e esvaziamento)
│   └── waveforms/      # figuras SVG/PNG, CSV ciclo a ciclo e sessão .gtkw (make wave-t0)
├── vhdl/               # RTL
│   ├── o1_pkg, register_file, alu, instruction_memory, data_memory   # componentes comuns
│   ├── cpu_top.vhd     #   O1: multiciclo (FSM)
│   ├── o2_pkg.vhd      #   O2: tipos dos registradores entre estágios
│   ├── unified_memory.vhd #  O2: memória unificada IF/MEM (MEM_UNIFICADA = true)
│   └── cpu_top_o2.vhd  #   O2: pipeline de 5 estágios, detecção estrutural e aborto
├── testbench/
│   ├── tb_cpu.vhd      #   testbench único (ORG=O2 instancia cpu_top_o2; outro valor usa a O1):
│   │                   #   carrega o .hex, conta ciclos/instruções,
│   │                   #   confere os registradores com o *_esperado.txt e grava métricas
│   └── unit/           #   testes isolados dos componentes (register_file, alu, memórias)
├── tracos/             # Traços de teste
│   ├── t0.asm          #   T0: traço limpo (sem conflitos), fonte em assembly
│   ├── t0.hex          #   T0 montado (uma instrução de 32 bits em hex por linha)
│   ├── t0_esperado.txt #   estado final esperado dos registradores ("reg valor_hex")
│   ├── s005 … s200.*   #   série S: T0 com 5, 10, 20, 50, 100 e 200 instruções úteis (gerada)
│   ├── tc.*            #   TC: conflito de controle (asm, hex e esperado)
│   ├── td.*            #   TD: conflito de dados RAW (asm, hex e esperado)
│   └── te.*            #   TE: conflito estrutural (asm, hex e esperado)
├── scripts/            # run_all.sh: compila, simula todos os traços e gera métricas e tabelas (R7)
│                       # tabelas_metricas.py: tabelas do relatório a partir do metricas.csv
│                       # run_ghdl_tests.sh: limpa, roda os testes unitários e o tb_cpu
│                       # gerar_serie_s.py: gera a série S a partir do T0 (make serie-s)
│                       # waveform_o2.py: figuras anotadas + .gtkw a partir do .ghw (make wave-t0)
├── build/              # Gerado pelo make (objetos do GHDL e ondas .ghw) — não versionado
├── isa_table_mips.md   # Tabela da ISA (mnemônico, formato, opcode/funct, RTL)
├── metricas.csv        # Métricas do R6 por organização × traço limpo (make metricas)
├── resultados/         # conflitos.csv e tabelas.md, gerados pelo run_all
└── Makefile
```

## Pré-requisitos

| Ferramenta | Uso | Verificar |
| --- | --- | --- |
| GHDL (≥ 4, com suporte a VHDL-2008) | compilar e simular | `ghdl --version` |
| GTKWave | visualizar as formas de onda | `gtkwave --version` |
| GNU Make | automatizar compilação/simulação | `make --version` |
| MARS 4.5 (Java) | montar os traços `.asm` e gerar o esperado | `java -jar Mars4_5.jar` |

## Como executar

Todos os comandos são rodados na raiz do repositório.

### Tudo com um comando (R7)

```bash
./scripts/run_all.sh
```

Compila, roda os testes unitários, simula os traços limpos (T0 e série S) na O1 e na O2, confere os
traços de conflito (TD, TE e TC abortam na O2 com o tipo, `hazard_pc` e `hazard_cycle` esperados e
rodam limpos na O1) e gera:

| Arquivo | Conteúdo |
| --- | --- |
| `metricas.csv` | métricas do R6 por organização × traço limpo |
| `resultados/conflitos.csv` | tipo, `hazard_pc` e `hazard_cycle` detectados em cada traço de conflito |
| `resultados/tabelas.md` | tabelas do relatório: T0, speedup, série S, ocupação por estágio e registro de conflitos |

Para no primeiro erro, com código de saída ≠ 0. Só precisa de `ghdl`, `make` e `python3` (bash 4+): os
`.hex` e os `_esperado.txt` estão versionados, então o MARS não é necessário. Com os períodos de clock
(R6, issue #21), as tabelas também trazem tempo de execução e speedup em tempo:

```bash
PERIODO_O1_NS=<período O1> PERIODO_O2_NS=<período O2> ./scripts/run_all.sh
```

### Comandos individuais

```bash
make sim                      # compila vhdl/ + tb_cpu, elabora e simula (padrão: O1, T0)
make test-unit                # testes isolados dos componentes (testbench/unit/)
make clean                    # apaga a pasta build/
```

`make sim` compila, elabora e simula; `make compile`, `make elaborate` e `make run` também podem ser chamados sozinhos.
`./scripts/run_ghdl_tests.sh` faz `make clean`, `make test-unit` e `make sim` em sequência.


### Parâmetros

Os parâmetros são passados como variáveis do `make` e viram *generics* do `tb_cpu`:

| Variável | Padrão | Significado |
| --- | --- | --- |
| `ORG` | `O1` | organização simulada (`O1` ou `O2`) |
| `SLOTS` | `1` | número de slots (ex.: `5` na O2) |
| `PROG` | `tracos/t0.hex` | programa carregado na memória |
| `ESPERADO` | `tracos/t0_esperado.txt` | estado final esperado dos registradores |
| `ABORTO` | `false` | `true` se o traço deve provocar aborto por conflito |
| `TIPO` | `0` | tipo de conflito esperado: `1` dados, `2` estrutural, `3` controle |
| `MEMUNI` | `false` | memória unificada (instruções + dados) |
| `PCESP` | — | `hazard_pc` esperado em hex, sem `0x` (ex.: `00000014`); opcional, falha a simulação se divergir |
| `STOP_TIME` | `200us` | limite de tempo simulado (rede de segurança) |

Exemplos:

```bash
make sim                                   # O1 executando o T0
make sim ORG=O2 SLOTS=5                    # O2 (pipeline) executando o T0
make sim ORG=O2 SLOTS=5 PROG=tracos/te.hex ESPERADO=tracos/te_esperado.txt ABORTO=true TIPO=2 MEMUNI=true PCESP=00000018   # TE: aborto estrutural
make sim ORG=O2 SLOTS=5 PROG=tracos/td.hex ESPERADO=tracos/td_esperado.txt ABORTO=true TIPO=1 PCESP=00000014   # TD: aborto por dados
make sim ORG=O2 SLOTS=5 PROG=tracos/tc.hex ESPERADO=tracos/tc_esperado.txt ABORTO=true TIPO=3 PCESP=00000018   # TC: aborto por controle
```

> O GHDL roda dentro de `build/` com caminhos relativos, porque o caminho absoluto da pasta
> pode ter acentos e isso quebra o `work-obj08.cf`. Por isso use sempre o `make`.

### Traços de conflito (O2)

Cada traço tem fonte (`.asm`), `.hex` (MARS) e `_esperado.txt`. Na O2 ele aborta; na O1, que
não tem conflitos, roda até o fim e confere os registradores com o esperado.

| Traço | Conflito | Instrução envolvida | `hazard_type` | `hazard_pc` | `hazard_cycle` | Comando (O2) |
| --- | --- | --- | --- | --- | --- | --- |
| TD | dados (RAW, distância 1) | `sub` consumidora | `01` | `0x14` | 7 | `make sim ORG=O2 SLOTS=5 PROG=tracos/td.hex ESPERADO=tracos/td_esperado.txt ABORTO=true TIPO=1 PCESP=00000014` |
| TE | estrutural (`MEM_UNIFICADA`) | `addi` em IF que não obteve a memória | `10` | `0x18` | 7 | `make sim ORG=O2 SLOTS=5 PROG=tracos/te.hex ESPERADO=tracos/te_esperado.txt ABORTO=true TIPO=2 MEMUNI=true PCESP=00000018` |
| TC | controle (`beq` tomado) | o `beq` | `11` | `0x18` | 9 | `make sim ORG=O2 SLOTS=5 PROG=tracos/tc.hex ESPERADO=tracos/tc_esperado.txt ABORTO=true TIPO=3 PCESP=00000018` |

Cada traço também tem casos que **não** podem abortar: o TD tem escrita em `$zero` e dependência a
distância 3; o TE roda limpo com `MEMUNI=false`; o TC tem um `beq` não tomado antes do tomado.

### Série S (R5)

Variações do T0 com 5, 10, 20, 50, 100 e 200 instruções úteis, para o gráfico de speedup por tamanho.
Cada `sNNN` é formado pelas *N* primeiras instruções da repetição do corpo do T0, seguidas de `break`.
Um prefixo de um programa sem conflitos continua sem conflitos, e cada cópia do T0 recalcula os
registradores que lê, então a série também é livre de conflitos. O script confere isso e monta o
`.hex` e o `_esperado.txt` no MARS:

```bash
make serie-s                                         # regenera tracos/s005 … s200 (só se o T0 mudar)
make sim ORG=O2 SLOTS=5 PROG=tracos/s200.hex ESPERADO=tracos/s200_esperado.txt
```

Na O2 cada traço leva *N* + 5 ciclos (*N* úteis + `break` + 4 de enchimento).
### Métricas (R6)

```bash
make metricas    # roda os traços limpos (T0 e a série S, quando existir) na O1 e na O2 e grava metricas.csv
```

Cada execução do `tb_cpu` acrescenta uma linha em `build/metricas.csv` (o cabeçalho é escrito quando o
arquivo está vazio); `make metricas` começa de um arquivo vazio e copia o resultado para `metricas.csv`
na raiz. As 8 primeiras colunas seguem o modelo do enunciado (seção 3.5):

| Coluna | Significado |
| --- | --- |
| `org`, `programa` | organização e traço (`.hex`) |
| `ciclos` | do 1º ciclo após o reset até o ciclo em que `done = 1`, **inclusive** |
| `instrucoes` | soma de `retired`: instruções úteis; o `break` **não** conta |
| `CPI`, `IPC` | `ciclos / instrucoes` e `instrucoes / ciclos` |
| `ocupacao` | fração dos `ciclos × NUM_SLOTS` com bit de `stage_valid` em 1 |
| `erros` | registradores que divergiram do `_esperado.txt` |
| `desfecho` | `done`, `aborto` (conflito) ou `tempo_esgotado` |
| `ocup_IF` … `ocup_WB` | ocupação de cada estágio da via 0 (bits 0..4 de `stage_valid`); a O1 só tem o slot 0 (`ocup_IF`) |
| `ocup_via0`, `ocup_via1` | ocupação média de cada via (bits 4..0 e 9..5); `ocup_via1` só existe com emissão dupla |

Tempo de execução (ciclos × período) e speedup dependem do período de clock de cada organização (R6).

### Ver as formas de onda

A simulação grava `build/<testbench>.ghw`:

```bash
gtkwave build/tb_cpu.ghw
```

Waveform anotada do T0 na O2 (figuras em `docs/waveforms/` e sessão pronta para o GTKWave, com sinais
agrupados por estágio, hex e marcadores de enchimento/esvaziamento):

```bash
make wave-t0
gtkwave build/t0_o2.ghw docs/waveforms/t0_o2.gtkw
```

O `scripts/waveform_o2.py` usa o `ghwdump`, que vem com o GHDL (variável `GHWDUMP` para indicar outro
caminho), e o ImageMagick (`magick`), opcional, para gerar os PNGs.

### Montar um traço novo (MARS)

1. Escreva `tracos/<nome>.asm`.
2. Gere o `.hex` (memória de dados começando no endereço 0, como a memória de dados do VHDL):

   ```bash
   java -jar Mars4_5.jar nc a mc CompactDataAtZero dump .text HexText tracos/<nome>.hex tracos/<nome>.asm
   ```

   Use `CompactDataAtZero`, e não `CompactTextAtZero`: com o texto no endereço 0, um `sw` em `0($zero)`
   tenta escrever no segmento de texto e o MARS aborta a execução. Como o `beq` é relativo ao PC,
   o `.hex` gerado é o mesmo nas duas configurações.

3. Rode no MARS e imprima os registradores para montar o `<nome>_esperado.txt`
   (formato `numero_do_registrador valor_hex`, uma linha por registrador; linhas com `#` são comentários):

   ```bash
   java -jar Mars4_5.jar nc mc CompactDataAtZero 4 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 tracos/<nome>.asm
   ```

   A mensagem `break instruction executed ... Processing terminated due to errors` no fim é esperada
   (é o `break` encerrando o programa). Qualquer outro erro antes dela indica problema no traço.

### Adicionar um arquivo VHDL novo

A lista `SOURCES` do `Makefile` é mantida **na mão**, em ordem de dependência (pacotes antes de quem os usa).
Ao criar um arquivo novo em `vhdl/` (ex.: componentes do O2), inclua-o em `SOURCES`, senão ele não é compilado.

### Detalhes de implementação (O1)

- Banco de registradores: reset síncrono na borda de subida, escrita na borda de descida, leituras assíncronas (incluindo `dbg_reg_addr`/`dbg_reg_data`).
- Memória de instruções: uma palavra hexadecimal de 32 bits por linha (generic `INIT_FILE`); endereços em bytes, alinhados em 4.
- Memória de dados: leitura combinacional (`MemRead`) e escrita na borda de subida (`MemWrite`). `slt` usa comparação *signed*.
- Na O1 as saídas de hazard ficam em zero. Como a interface R3 não expõe a memória de dados, o `tb_cpu` confere `sw` por meio de `lw` e dos registradores esperados; os testes unitários verificam os componentes isoladamente.

## Regras de equipe

- **Branches:** `main` guarda só versões estáveis/entregáveis; o trabalho do dia a dia vai em `develop`,
  e cada tarefa em uma branch própria criada a partir de `develop` (ex.: `issue-7-traco-t0`).
- **Ninguém faz push direto em `main`.** Toda mudança entra por *Pull Request*.
- **Todo PR é revisado e aprovado por outro integrante** (não pelo autor) antes do merge.
- O PR referencia a issue que resolve (`Closes #N`) e só é aberto com `make sim` rodando sem erro.
- Cada issue preenche o campo **"Usou IA?"** (sim/não e para quê), que alimenta o Apêndice C do relatório.
- Arquivos gerados (`build/`, `*.ghw`, `*.vcd`, `*.cf`) não são versionados.

## Integrantes

- Aurelio
- João Guilherme
- Osean
