# Tabela da ISA MIPS

Esta tabela descreve o subconjunto mínimo de instruções da ISA MIPS, conforme solicitado no issue #1.

**Fonte:** Patterson, D. A., & Hennessy, J. L. *Organização e Projeto de Computadores: A Interface Hardware/Software*.

| Mnemônico | Formato | Opcode (hex) | Funct (hex) | RTL |
| :--- | :---: | :---: | :---: | :--- |
| `add` | R | `0x00` | `0x20` | `rd ← rs + rt` |
| `sub` | R | `0x00` | `0x22` | `rd ← rs - rt` |
| `addi` | I | `0x08` | - | `rt ← rs + imm` |
| `and` | R | `0x00` | `0x24` | `rd ← rs & rt` |
| `or` | R | `0x00` | `0x25` | `rd ← rs \| rt` |
| `slt` | R | `0x00` | `0x2a` | `rd ← (rs < rt) ? 1 : 0` |
| `lw` | I | `0x23` | - | `rt ← Mem[rs + imm]` |
| `sw` | I | `0x2b` | - | `Mem[rs + imm] ← rt` |
| `beq` | I | `0x04` | - | `if (rs == rt) PC ← PC + 4 + (imm << 2)` |
| `break` | R | `0x00` | `0x0d` | `exception` |

---
*Nota: Para instruções do tipo R, o opcode é sempre `0x00` e a distinção é feita pelo campo `funct`. Para instruções do tipo I, utiliza-se o opcode para identificação.*
