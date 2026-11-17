#!/usr/bin/env python3
"""Tabelas do relatório a partir do metricas.csv e do conflitos.csv (issue #20).

Uso:
    python3 scripts/tabelas_metricas.py metricas.csv resultados/conflitos.csv > resultados/tabelas.md

Só reorganiza os números medidos pelo tb_cpu; não inventa nem estima valores.
Tempo de execução e speedup em tempo dependem do período de clock de cada organização
(R6, issue #21): informe-os em ns para incluí-los, por exemplo
    PERIODO_O1_NS=1.2 PERIODO_O2_NS=0.4 python3 scripts/tabelas_metricas.py ...
"""
import csv
import os
import re
import sys

ESTAGIOS = ["IF", "ID", "EX", "MEM", "WB"]


def ler(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter=";"))


def nome(prog):
    return os.path.splitext(os.path.basename(prog))[0].upper()


def ordem(n):
    m = re.match(r"S(\d+)$", n)
    return (1, int(m.group(1))) if m else (0, n)


def f3(x):
    return f"{float(x):.3f}".replace(".", ",")


def pct(x):
    return f"{100 * float(x):.1f} %".replace(".", ",")


def tabela(cab, linhas):
    out = ["| " + " | ".join(cab) + " |", "|" + "|".join(" --- " for _ in cab) + "|"]
    out += ["| " + " | ".join(str(c) for c in l) + " |" for l in linhas]
    return "\n".join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    met = [r for r in ler(sys.argv[1]) if r["desfecho"] == "done"]
    conf = ler(sys.argv[2])
    por = {(r["org"], nome(r["programa"])): r for r in met}
    tracos = sorted({nome(r["programa"]) for r in met}, key=ordem)
    per = {o: os.environ.get(f"PERIODO_{o}_NS") for o in ("O1", "O2")}
    com_tempo = all(per.values())

    print("# Tabelas de resultados\n")
    print("Geradas por `scripts/run_all.sh` a partir de `metricas.csv` e `resultados/conflitos.csv`. "
          "Ciclos contados do 1º ciclo após o reset até `done = 1`, inclusive; o `break` não entra em "
          "instruções, CPI e IPC.\n")

    # 1. T0
    print("## T0 por organização\n")
    cab = ["Organização", "Ciclos", "Instruções", "CPI", "IPC", "Ocupação"]
    if com_tempo:
        cab += ["Período (ns)", "Tempo (ns)"]
    linhas = []
    for o in ("O1", "O2"):
        r = por.get((o, "T0"))
        if r:
            l = [o, r["ciclos"], r["instrucoes"], f3(r["CPI"]), f3(r["IPC"]), pct(r["ocupacao"])]
            if com_tempo:
                l += [per[o].replace(".", ","), f3(int(r["ciclos"]) * float(per[o]))]
            linhas.append(l)
    print(tabela(cab, linhas) + "\n")

    # 2. speedup por traço
    print("## Speedup da O2 sobre a O1\n")
    cab = ["Traço", "Instruções", "Ciclos O1", "Ciclos O2", "Speedup em ciclos (O1/O2)"]
    if com_tempo:
        cab += ["Tempo O1 (ns)", "Tempo O2 (ns)", "Speedup em tempo"]
    cab += ["Speedup ideal (5 estágios)"]
    linhas = []
    for t in tracos:
        a, b = por.get(("O1", t)), por.get(("O2", t))
        if not (a and b):
            continue
        c1, c2 = int(a["ciclos"]), int(b["ciclos"])
        l = [t, a["instrucoes"], c1, c2, f3(c1 / c2)]
        if com_tempo:
            t1, t2 = c1 * float(per["O1"]), c2 * float(per["O2"])
            l += [f3(t1), f3(t2), f3(t1 / t2)]
        l += ["5"]
        linhas.append(l)
    print(tabela(cab, linhas) + "\n")
    if not com_tempo:
        print("Tempo de execução e speedup em tempo dependem do período de clock de cada organização "
              "(R6, issue #21); defina `PERIODO_O1_NS` e `PERIODO_O2_NS` para incluí-los.\n")
    else:
        print(f"Períodos de clock: O1 = {per['O1'].replace('.', ',')} ns, "
              f"O2 = {per['O2'].replace('.', ',')} ns "
              "(critério e justificativa em `docs/periodo-clock.md`).\n")

    # 3. série S
    serie = [t for t in tracos if t.startswith("S")]
    if serie:
        print("## Série S: efeito do enchimento e do esvaziamento\n")
        cab = ["Traço", "Instruções", "Ciclos O1", "Ciclos O2", "CPI O1", "CPI O2",
               "Ciclos O2 − instruções", "Ocupação O2"]
        linhas = []
        for t in serie:
            a, b = por.get(("O1", t)), por.get(("O2", t))
            if a and b:
                linhas.append([t, b["instrucoes"], a["ciclos"], b["ciclos"], f3(a["CPI"]), f3(b["CPI"]),
                               int(b["ciclos"]) - int(b["instrucoes"]), pct(b["ocupacao"])])
        print(tabela(cab, linhas) + "\n")

    # 4. ocupação por estágio
    print("## Ocupação por estágio e por via (O2)\n")
    cab = ["Traço"] + ESTAGIOS + ["Via 0", "Via 1"]
    linhas = []
    for t in tracos:
        r = por.get(("O2", t))
        if r:
            linhas.append([t] + [pct(r[f"ocup_{e}"]) for e in ESTAGIOS] + [pct(r["ocup_via0"]),
                          pct(r["ocup_via1"]) if r.get("ocup_via1") else "—"])
    print(tabela(cab, linhas) + "\n")
    print("Na O1 só existe o slot 0 (`stage_valid(0)`): " + ", ".join(
        f"{t} {pct(por[('O1', t)]['ocupacao'])}" for t in tracos if ("O1", t) in por) + ".\n")

    # 5. conflitos
    print("## Registro de conflitos\n")
    tipos = {"01": "dados", "10": "estrutural", "11": "controle"}
    cab = ["Traço", "Organização", "Tipo esperado", "Tipo detectado", "hazard_pc", "hazard_cycle", "Resultado"]
    linhas = []
    for r in conf:
        if r["organizacao"] != "O2":
            continue
        linhas.append([r["traco"].upper(), r["organizacao"],
                       f'{r["tipo_esperado"]} ({tipos.get(r["tipo_esperado"], "?")})',
                       f'{r["tipo_detectado"]} ({tipos.get(r["tipo_detectado"], "?")})',
                       r["hazard_pc"], r["hazard_cycle"], r["resultado"]])
    print(tabela(cab, linhas) + "\n")
    o1 = [r["traco"].upper() for r in conf if r["organizacao"] == "O1" and r["resultado"] == "ok"]
    if o1:
        print(f"Na O1 os traços {', '.join(o1)} executam até o fim sem conflito e conferem o esperado.")


if __name__ == "__main__":
    main()
