# MicroProj-AOC-Aurelio_JoaoGuilherme-Osean

## Organização O1 (multiciclo)

- [FSM, caminho de dados e ISA da O1](docs/fsm-o1.md): premissas, diagrama de datapath com registradores e muxes, estados, sinais de controle e ciclos por classe de instrução.

## VHDL-2008

O RTL da O1 fica em `vhdl/`: banco de registradores, ALU, memórias separadas e `cpu_top`. O testbench de integração único da seção 7 é `testbench/tb_cpu.vhd`; para compilar e executar a integração com o Makefile:

```sh
make sim
```

Os testbenches isolados dos componentes ficam em `testbench/` e podem ser executados com `make test-unit`. Eles complementam, mas não duplicam nem substituem `tb_cpu.vhd`.

O banco escreve na borda de descida e tem leituras assíncronas, incluindo `dbg_reg_addr`/`dbg_reg_data`. A ROM recebe uma palavra hexadecimal de 32 bits por linha pelo genérico `INIT_FILE`; os endereços de memória são em bytes e devem ser alinhados em 4 bytes. `MemRead` habilita a leitura combinacional da memória de dados e `MemWrite` habilita a escrita na borda de subida. `slt` usa comparação signed.
