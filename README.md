# MicroProj-AOC — Aurelio, João Guilherme e Osean

Microprojeto de Arquitetura e Organização de Computadores (2026): processador MIPS
(subconjunto mínimo da ISA) descrito em **VHDL-2008**, simulado com **GHDL** e
inspecionado no **GTKWave**.

- **O1** — organização multiciclo.
- **O2** — organização em pipeline, com detecção de conflitos (dados, estrutural e controle).

As instruções suportadas estão em [`isa_table_mips.md`](isa_table_mips.md).

## Documentação da O1

- [FSM, caminho de dados e ISA da O1](docs/fsm-o1.md): premissas, diagrama do datapath com registradores e muxes, estados, sinais de controle e ciclos por classe.

## Estrutura de pastas

```
.
├── docs/
│   └── fsm-o1.md       # FSM, caminho de dados e ciclos por classe da O1
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
│   ├── td.*            #   TD: conflito de dados RAW (asm, hex e esperado)
│   └── te.*            #   TE: conflito estrutural (asm, hex e esperado)
├── scripts/            # run_ghdl_tests.sh: limpa, roda os testes unitários e o tb_cpu
├── build/              # Gerado pelo make (objetos do GHDL e ondas .ghw) — não versionado
├── isa_table_mips.md   # Tabela da ISA (mnemônico, formato, opcode/funct, RTL)
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
```

> O GHDL roda dentro de `build/` com caminhos relativos, porque o caminho absoluto da pasta
> pode ter acentos e isso quebra o `work-obj08.cf`. Por isso use sempre o `make`.

### Ver as formas de onda

A simulação grava `build/<testbench>.ghw`:

```bash
gtkwave build/tb_cpu.ghw
```

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
