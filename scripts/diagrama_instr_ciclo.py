#!/usr/bin/env python3
"""Diagramas instrução × ciclo do T0 (seção 6.1 do enunciado, issue #22).

Uso:
    python3 scripts/diagrama_instr_ciclo.py build/t0_o1.ghw build/t0_o2.ghw tracos/t0.asm docs

Lê os dumps GHW da simulação do T0 na O1 e na O2 e gera:
    docs/diagrama-instrucao-ciclo.md       quatro tabelas (O1 e O2; 10 primeiras e 3 últimas)
    docs/diagramas/t0_<org>_instr_ciclo.csv a tabela completa, todas as instruções e ciclos

Cada linha é uma instrução e cada coluna um ciclo; a célula mostra o estágio.
Ciclo 1 = primeiro ciclo após o reset, amostrado na borda de descida (convenção do tb_cpu).
  * O2: o estágio de cada instrução vem do PC presente em IF, IF/ID, ID/EX, EX/MEM e MEM/WB
    (mesma leitura do scripts/waveform_o2.py).
  * O1: o estágio vem do estado da FSM: FETCH = IF, DECODE = ID, *_EXEC/ADDR/BRANCH = EX,
    MEM_READ/MEM_WRITE = MEM, *_WB = WB; HALT (após o break, com done = 1) aparece como HALT.
"""
import csv
import os
import sys

sys.dont_write_bytecode = True   # não deixar scripts/__pycache__ no repositório
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from waveform_o2 import Signals, build_table, load_asm, sample_cycles, STAGES  # noqa: E402

ESTADO_O1 = {"fetch": "IF", "decode": "ID", "r_exec": "EX", "addi_exec": "EX", "addr": "EX",
             "branch": "EX", "mem_read": "MEM", "mem_write": "MEM", "r_wb": "WB",
             "addi_wb": "WB", "mem_wb": "WB", "halt": "HALT"}
D1 = "/tb_cpu/gen_o1/dut/"


def grade_o1(ghw):
    """{pc: {ciclo: estágio}} e número de ciclos, a partir do estado da FSM da O1."""
    sig = Signals(ghw)
    i_state = sig.rng(D1 + "state")[0]
    grade, atual, n = {}, None, 0
    for k, s in enumerate(sample_cycles(sig), start=1):
        est = s.get(i_state)
        if est == "fetch":
            atual = sig.num(s, D1 + "pc")       # PC da instrução sendo buscada
        if atual is not None:
            grade.setdefault(atual, {})[k] = ESTADO_O1[est]
        n = k
        if sig.bits(s, "/tb_cpu/done") == "1":
            break
    return grade, n


def grade_o2(ghw):
    rows = build_table(Signals(ghw))
    grade = {}
    for r in rows:
        for st, k in STAGES:
            if r[f"{k}_v"] and r[f"{k}_pc"] is not None:
                grade.setdefault(r[f"{k}_pc"], {})[r["ciclo"]] = st
    return grade, rows[-1]["ciclo"]


def md(grade, pcs, asm, titulo):
    ciclos = sorted({c for pc in pcs for c in grade[pc]})
    c0, c1 = ciclos[0], ciclos[-1]
    cols = list(range(c0, c1 + 1))
    out = [f"#### {titulo}", "",
           "| Instrução | " + " | ".join(f"C{c}" for c in cols) + " |",
           "| --- |" + " :---: |" * len(cols)]
    for pc in pcs:
        nome = f"`0x{pc:02X}` {asm.get(pc, '')}"
        out.append(f"| {nome} | " + " | ".join(grade[pc].get(c, "") for c in cols) + " |")
    return "\n".join(out) + "\n"


def salvar_csv(grade, n, asm, path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["pc", "instrucao"] + [f"C{c}" for c in range(1, n + 1)])
        for pc in sorted(grade):
            w.writerow([f"0x{pc:02X}", asm.get(pc, "")] + [grade[pc].get(c, "") for c in range(1, n + 1)])


def conferir(grade, n, org, asm):
    """Checagens contra a simulação: cada instrução passa pelos estágios em ordem, uma vez."""
    ordem = ["IF", "ID", "EX", "MEM", "WB"]
    for pc, cel in grade.items():
        seq = [cel[c] for c in sorted(cel)]
        idx = [ordem.index(s) for s in seq if s in ordem]
        if idx != sorted(idx) or idx[0] != 0:
            sys.exit(f"{org}: estágios fora de ordem em 0x{pc:02X}: {seq}")
        if org == "O2" and seq != ordem:
            sys.exit(f"O2: instrução 0x{pc:02X} não passou pelos 5 estágios: {seq}")
    if sorted(grade) != sorted(asm):
        sys.exit(f"{org}: instruções executadas diferem do programa")


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    ghw1, ghw2, asm_path, docs = sys.argv[1:]
    asm = load_asm(asm_path)
    g1, n1 = grade_o1(ghw1)
    g2, n2 = grade_o2(ghw2)
    conferir(g1, n1, "O1", asm)
    conferir(g2, n2, "O2", asm)

    os.makedirs(os.path.join(docs, "diagramas"), exist_ok=True)
    salvar_csv(g1, n1, asm, os.path.join(docs, "diagramas", "t0_o1_instr_ciclo.csv"))
    salvar_csv(g2, n2, asm, os.path.join(docs, "diagramas", "t0_o2_instr_ciclo.csv"))

    pcs = sorted(asm)
    primeiras, ultimas = pcs[:10], pcs[-3:]
    prog = os.path.basename(asm_path)
    txt = [
        "# Diagramas instrução × ciclo do T0 (issue #22)", "",
        f"Gerados de `{prog}` simulado na O1 e na O2 (`make diagramas`), no formato da seção 6.1 do "
        "enunciado: cada linha é uma instrução, cada coluna um ciclo e a célula mostra o estágio. "
        "Ciclo 1 = primeiro ciclo após o reset (convenção do `tb_cpu`). Nada é escrito à mão: o "
        "script lê os dumps GHW e confere que cada instrução percorre os estágios em ordem.", "",
        f"- **O1 (multiciclo):** o estágio vem do estado da FSM (`FETCH` = IF, `DECODE` = ID, "
        "`*_EXEC`/`ADDR`/`BRANCH` = EX, `MEM_READ`/`MEM_WRITE` = MEM, `*_WB` = WB). Uma instrução "
        f"por vez; o T0 inteiro leva {n1} ciclos. `HALT` é o ciclo em que `done = 1`, depois do `break`.",
        f"- **O2 (pipeline):** o estágio vem do PC presente em IF e nos registradores IF/ID, ID/EX, "
        f"EX/MEM e MEM/WB. Uma instrução entra por ciclo; o T0 inteiro leva {n2} ciclos e o `break` "
        f"conclui em WB no C{n2} (`done = 1`).", "",
        "As 3 últimas instruções do T0 são os dois `beq` (não tomados) e o `break`.", "",
        "## O1 — multiciclo", "",
        md(g1, primeiras, asm, "10 primeiras instruções"),
        md(g1, ultimas, asm, "3 últimas instruções"),
        "## O2 — pipeline de 5 estágios", "",
        md(g2, primeiras, asm, "10 primeiras instruções"),
        md(g2, ultimas, asm, "3 últimas instruções"),
        "## Tabelas completas", "",
        "Todas as instruções e todos os ciclos: `docs/diagramas/t0_o1_instr_ciclo.csv` e "
        "`docs/diagramas/t0_o2_instr_ciclo.csv` (abrem em planilha, separador `;`).", "",
    ]
    with open(os.path.join(docs, "diagrama-instrucao-ciclo.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(txt))
    print(f"O1: {n1} ciclos, O2: {n2} ciclos; {len(asm)} instruções conferidas em ordem nas duas")


if __name__ == "__main__":
    main()
