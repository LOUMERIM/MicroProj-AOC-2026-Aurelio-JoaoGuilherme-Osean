# MicroProj-AOC-Aurelio_JoaoGuilherme-Osean

## Organização O1 (multiciclo)

- [FSM, caminho de dados e ISA da O1](docs/fsm-o1.md): premissas, diagrama de datapath com registradores e muxes, estados, sinais de controle e ciclos por classe de instrução.

## VHDL-2008

Os componentes da O1 estão em `src/rtl/`: banco de registradores, ALU, memórias separadas e `cpu_top` com a FSM multiciclo. Para executar os testes unitários e o testbench de integração da seção 7 do enunciado com GHDL:

```sh
./scripts/run_ghdl_tests.sh
```

O banco é zerado por reset síncrono na borda de subida, escreve na borda de descida e tem leituras assíncronas, incluindo `dbg_reg_addr`/`dbg_reg_data`. A ROM recebe uma palavra hexadecimal de 32 bits por linha pelo genérico `INIT_FILE`; o endereço das memórias é em bytes e deve ser alinhado em 4 bytes. `MemRead` habilita a leitura combinacional da memória de dados e `MemWrite` habilita a escrita na borda de subida. `slt` usa comparação signed. As leituras das memórias são combinacionais para atender os estados `FETCH` e `MEM_READ` descritos na FSM.

`tests/tb_register_file.vhd`, `tests/tb_alu.vhd` e `tests/tb_memories.vhd` verificam os componentes isoladamente. `tests/tb_cpu.vhd` exercita `cpu_top` com a interface R3, executando `tracos/t0.hex`, conferindo os registradores finais e acrescentando uma linha a `metricas.csv`. O T0 tem 30 instruções úteis (o `break` não entra em `retired`) e seus fontes/saídas esperadas ficam em `tracos/`.

O testbench aceita os genéricos da seção 7 e inclui a verificação parametrizada de `hazard_pc` para traços com aborto. Para a O1, as saídas de hazard devem permanecer em zero. Como a interface R3 não expõe leitura de depuração da memória de dados, a integração confere escritas com `sw` por meio de `lw` subsequente e de registradores esperados; o testbench unitário da memória verifica diretamente valores não nulos.
