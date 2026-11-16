# MicroProj-AOC-Aurelio_JoaoGuilherme-Osean

## Organização O1 (multiciclo)

- [FSM, caminho de dados e ISA da O1](docs/fsm-o1.md): premissas, diagrama de datapath com registradores e muxes, estados, sinais de controle e ciclos por classe de instrução.

## VHDL-2008

Os componentes independentes da O1 estão em `src/rtl/`: banco de registradores, ALU e memórias separadas. Para compilar e executar os testbenches isolados com GHDL:

```sh
./scripts/run_ghdl_tests.sh
```

O banco escreve na borda de descida e tem leituras assíncronas, incluindo `dbg_reg_addr`/`dbg_reg_data`. A ROM recebe uma palavra hexadecimal de 32 bits por linha pelo genérico `INIT_FILE`; o endereço das memórias é em bytes e deve ser alinhado em 4 bytes. `MemRead` habilita a leitura combinacional da memória de dados e `MemWrite` habilita a escrita na borda de subida. `slt` usa comparação signed. As leituras das memórias são combinacionais para atender os estados `FETCH` e `MEM_READ` descritos na FSM.

Os testbenches em `tests/` são testes **unitários** dos componentes, conforme o escopo do issue #4. Eles não são o `tb_cpu.vhd` de integração da seção 7 do enunciado: esse testbench requer uma entidade `cpu_top` com a interface R3, que será implementada junto com a FSM/top-level. Portanto, os testes unitários não verificam execução de traços, contagem de ciclos, `retired`, `stage_valid` ou geração de `metricas.csv`.
