#!/usr/bin/env python3
"""Tabela do traço T0 (seção 6 do enunciado): endereço, instrução, registradores lidos e
escritos e distância até o produtor mais próximo.

Uso:
    python3 scripts/tabela_t0.py tracos/t0.asm docs/tabela-t0.md

Distância = posição da consumidora − posição da produtora mais recente de um dos registradores
que ela lê (1 = instrução imediatamente anterior). Escritas em $zero não geram dependência.
Como o T0 não tem desvio tomado, a ordem estática é a ordem de execução. O script falha se
alguma distância for 1 ou 2 (conflito de dados na O2), isto é, confere que o T0 é limpo.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gerar_serie_s import regs_da_instr, NOMES  # noqa: E402
from waveform_o2 import load_asm  # noqa: E402

NOME = {v: f"${k}" for k, v in reversed(list(NOMES.items()))}   # 8 -> $t0 (nome canônico)


def nome(r):
    return NOME[r]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    asm_path, saida = sys.argv[1:]
    asm = load_asm(asm_path)
    pcs = sorted(asm)
    linhas, produtora, dist_min = [], {}, None
    for k, pc in enumerate(pcs):
        texto = asm[pc]
        if texto.split()[0] == "break":
            lidos, dest = [], None
        else:
            dest, lidos = regs_da_instr(texto)
        lidos_ef = sorted({r for r in lidos if r != 0})
        cand = [(k - produtora[r][0], r) for r in lidos_ef if r in produtora]
        if cand:
            d, r = min(cand)
            pk = produtora[r][0]
            prod = f"`0x{pcs[pk]:02X}` {asm[pcs[pk]]} (via {nome(r)})"
            dist = str(d)
            dist_min = d if dist_min is None else min(dist_min, d)
            if d < 3:
                sys.exit(f"conflito de dados no T0: 0x{pc:02X} {texto} a distância {d} de 0x{pcs[pk]:02X}")
        else:
            prod, dist = "—", "—"
        linhas.append((k + 1, pc, texto, ", ".join(nome(r) for r in lidos_ef) or "—",
                       nome(dest) if dest not in (None, 0) else "—", prod, dist))
        if dest not in (None, 0):
            produtora[dest] = (k,)

    out = ["# Traço T0: endereços, registradores e distâncias (seção 6 do enunciado)", "",
           f"Gerada por `scripts/tabela_t0.py` a partir de `{os.path.basename(asm_path)}` "
           "(`make tabela-t0`). Nada é digitado à mão.", "",
           "- **Lê / Escreve:** registradores usados pela instrução. Leituras de `$zero` e escritas em "
           "`$zero` não geram dependência (R1).",
           "- **Produtor mais próximo:** a instrução anterior que escreveu o registrador lido há menos "
           "tempo, e por qual registrador.",
           "- **Distância:** 1 = instrução imediatamente anterior. Na O2 as distâncias **1 e 2 são "
           "conflito de dados**; a distância 3 não é (o banco escreve na 1ª metade do ciclo e lê na 2ª).",
           "- `—` em Produtor/Distância: a instrução só lê `$zero` ou nenhum registrador "
           "(inclui o `break`).", "",
           "| # | Endereço | Instrução | Lê | Escreve | Produtor mais próximo | Distância |",
           "| ---: | :---: | --- | --- | :---: | --- | :---: |"]
    for n, pc, texto, lê, esc, prod, dist in linhas:
        out.append(f"| {n} | `0x{pc:02X}` | `{texto}` | {lê} | {esc} | {prod} | {dist} |")
    com_dep = sum(1 for l in linhas if l[6] != "—")
    out += ["", f"**Resumo:** {len(linhas)} instruções (32 úteis + `break`); {com_dep} têm dependência de "
            f"dados e **a menor distância é {dist_min}**, ou seja, nenhuma está a distância 1 ou 2: o T0 "
            "não tem conflito de dados na O2. O mesmo vale para a O1, que não tem conflitos.", ""]
    os.makedirs(os.path.dirname(os.path.abspath(saida)), exist_ok=True)
    with open(saida, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"{len(linhas)} instruções; menor distância = {dist_min}; escrito em {saida}")


if __name__ == "__main__":
    main()
