#!/usr/bin/env python3
"""Gráficos do relatório a partir do metricas.csv (issue #23). Sem dependências: gera SVG.

Uso:
    python3 scripts/graficos.py metricas.csv resultados/graficos

Gera:
    cpi_t0.svg            CPI por organização no T0 (barras, uma por organização)
    speedup_t0.svg        speedup medido da O2 sobre a O1 no T0, ao lado do ideal
    speedup_tamanho.svg   speedup da O2 × tamanho do traço (série S), eixo x logarítmico

Speedup = tempo O1 / tempo O2 = (ciclos O1 × período O1) / (ciclos O2 × período O2).
Períodos em ns por PERIODO_O1_NS e PERIODO_O2_NS (padrão 0,22 ns nas duas, docs/periodo-clock.md).
Speedup ideal = CPI da O1 ÷ CPI ideal do pipeline (1), com a razão dos períodos: o que a O2 faria sem os
ciclos de enchimento e esvaziamento (a mesma referência de resultados/tabelas.md). Medido / ideal =
instruções ÷ ciclos da O2.
Só desenha números medidos pelo tb_cpu; nada é estimado.
"""
import csv
import math
import os
import re
import sys
from html import escape

# Paleta de referência (validada: O1 = slot 1 azul, O2 = slot 2 laranja; ideal = neutro)
COR = {"O1": "#2a78d6", "O2": "#eb6834", "ideal": "#8a8984",
       "texto": "#0b0b0b", "texto2": "#52514e", "grade": "#e6e5e1", "eixo": "#9b9a95",
       "fundo": "#fcfcfb"}
W, H = 640, 420
M = {"l": 64, "r": 24, "t": 72, "b": 76}          # margens da área de plotagem
FONTE = 'font-family="Inter, DejaVu Sans, Helvetica, Arial, sans-serif"'


def num(x):
    return f"{x:.2f}".replace(".", ",")


def ler(path):
    with open(path, encoding="utf-8") as f:
        linhas = [r for r in csv.DictReader(f, delimiter=";") if r["desfecho"] == "done"]
    dados = {}
    for r in linhas:
        nome = os.path.splitext(os.path.basename(r["programa"]))[0].upper()
        dados[(r["org"], nome)] = r
    return dados


def svg(titulo, subtitulo, corpo, rodape):
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" {FONTE}>',
        f'<rect width="100%" height="100%" fill="{COR["fundo"]}"/>',
        f'<text x="{M["l"]}" y="28" font-size="17" font-weight="600" fill="{COR["texto"]}">{escape(titulo)}</text>',
        f'<text x="{M["l"]}" y="48" font-size="12" fill="{COR["texto2"]}">{escape(subtitulo)}</text>',
        *corpo,
        f'<text x="{M["l"]}" y="{H - 10}" font-size="10.5" fill="{COR["texto2"]}">{escape(rodape)}</text>',
        "</svg>"])


def eixo_y(vmax, passo, rotulo):
    """Grade horizontal recessiva + rótulos do eixo y; devolve (elementos, função y)."""
    x0, x1 = M["l"], W - M["r"]
    y0, y1 = H - M["b"], M["t"]
    y = lambda v: y0 - (y0 - y1) * v / vmax
    el = []
    v = 0.0
    while v <= vmax + 1e-9:
        el.append(f'<line x1="{x0}" y1="{y(v):.1f}" x2="{x1}" y2="{y(v):.1f}" '
                  f'stroke="{COR["grade"] if v else COR["eixo"]}" stroke-width="1"/>')
        el.append(f'<text x="{x0 - 8}" y="{y(v) + 4:.1f}" font-size="11" text-anchor="end" '
                  f'fill="{COR["texto2"]}">{num(v) if passo < 1 else int(v)}</text>')
        v += passo
    el.append(f'<text transform="translate(16,{(y0 + y1) / 2:.0f}) rotate(-90)" font-size="11.5" '
              f'text-anchor="middle" fill="{COR["texto2"]}">{escape(rotulo)}</text>')
    return el, y


def barra(x, larg, y_topo, y_base, cor, tracejada=False):
    """Barra vertical com cantos de 4 px só no topo, ancorada na linha de base."""
    r = 4
    h = y_base - y_topo
    d = (f"M{x},{y_base} V{y_topo + r} Q{x},{y_topo} {x + r},{y_topo} H{x + larg - r} "
         f"Q{x + larg},{y_topo} {x + larg},{y_topo + r} V{y_base} Z")
    if tracejada:
        return (f'<path d="{d}" fill="{COR["fundo"]}" stroke="{cor}" stroke-width="2" '
                f'stroke-dasharray="6 4"/>')
    return f'<path d="{d}" fill="{cor}"/>' if h > 0 else ""


def grafico_cpi(dados, saida):
    orgs = [o for o in ("O1", "O2") if (o, "T0") in dados]
    cpi = {o: float(dados[(o, "T0")]["CPI"]) for o in orgs}
    vmax = math.ceil(max(cpi.values()) + 0.5)
    el, y = eixo_y(vmax, 1, "CPI (ciclos por instrução)")
    larg, gap = 110, 90
    x_ini = M["l"] + (W - M["l"] - M["r"] - (len(orgs) * larg + (len(orgs) - 1) * gap)) / 2
    for i, o in enumerate(orgs):
        x = x_ini + i * (larg + gap)
        el.append(barra(x, larg, y(cpi[o]), y(0), COR[o]))
        el.append(f'<text x="{x + larg / 2}" y="{y(cpi[o]) - 8:.1f}" font-size="13" font-weight="600" '
                  f'text-anchor="middle" fill="{COR["texto"]}">{num(cpi[o])}</text>')
        nome = "O1 (multiciclo)" if o == "O1" else "O2 (pipeline)"
        el.append(f'<text x="{x + larg / 2}" y="{y(0) + 20:.1f}" font-size="12" text-anchor="middle" '
                  f'fill="{COR["texto"]}">{nome}</text>')
    # referência: CPI ideal do pipeline = 1
    el.append(f'<line x1="{M["l"]}" y1="{y(1):.1f}" x2="{W - M["r"]}" y2="{y(1):.1f}" '
              f'stroke="{COR["ideal"]}" stroke-width="1.5" stroke-dasharray="6 4"/>')
    el.append(f'<text x="{W - M["r"]}" y="{y(1) - 6:.1f}" font-size="11" text-anchor="end" '
              f'fill="{COR["texto2"]}">CPI ideal do pipeline = 1</text>')
    n = dados[(orgs[0], "T0")]["instrucoes"]
    ciclos = ", ".join(f'{o}: {dados[(o, "T0")]["ciclos"]} ciclos' for o in orgs)
    with open(saida, "w", encoding="utf-8") as f:
        f.write(svg("CPI por organização — T0",
                    f"{n} instruções úteis ({ciclos}); menor é melhor",
                    el, "Fonte: metricas.csv (tb_cpu). O break não entra no CPI."))


def speedup(dados, traco, per):
    a, b = dados[("O1", traco)], dados[("O2", traco)]
    return (int(a["ciclos"]) * per["O1"]) / (int(b["ciclos"]) * per["O2"])


def ideal(dados, traco, per):
    """CPI da O1 ÷ 1 (CPI ideal do pipeline), corrigido pela razão dos períodos."""
    return float(dados[("O1", traco)]["CPI"]) * per["O1"] / per["O2"]


def grafico_speedup(dados, per, saida):
    s = speedup(dados, "T0", per)
    ide = ideal(dados, "T0", per)
    vmax = math.ceil(ide) + 1
    el, y = eixo_y(vmax, 1, "Speedup da O2 sobre a O1")
    larg, gap = 110, 90
    x_ini = M["l"] + (W - M["l"] - M["r"] - (2 * larg + gap)) / 2
    itens = [("Medido", s, COR["O2"], False), ("Ideal (CPI da O1 ÷ 1)", ide, COR["ideal"], True)]
    for i, (rot, v, cor, trac) in enumerate(itens):
        x = x_ini + i * (larg + gap)
        el.append(barra(x, larg, y(v), y(0), cor, trac))
        el.append(f'<text x="{x + larg / 2}" y="{y(v) - 8:.1f}" font-size="13" font-weight="600" '
                  f'text-anchor="middle" fill="{COR["texto"]}">{num(v)}×</text>')
        el.append(f'<text x="{x + larg / 2}" y="{y(0) + 20:.1f}" font-size="12" text-anchor="middle" '
                  f'fill="{COR["texto"]}">{escape(rot)}</text>')
    efic = 100 * s / ide
    with open(saida, "w", encoding="utf-8") as f:
        f.write(svg("Speedup da O2 sobre a O1 — T0",
                    f"medido = tempo O1 / tempo O2 = {num(s)}× ({f'{efic:.1f}'.replace('.', ',')} % do ideal: só enchimento e esvaziamento)",
                    el, f"Fonte: metricas.csv; períodos O1 = {num(per['O1'])} ns e O2 = {num(per['O2'])} ns "
                        f"(docs/periodo-clock.md)."))


def grafico_tamanho(dados, per, saida):
    serie = sorted((int(m.group(1)), t) for (o, t) in dados if o == "O2"
                   for m in [re.match(r"S(\d+)$", t)] if m and ("O1", t) in dados)
    if not serie:
        sys.exit("metricas.csv não tem a série S")
    pts = [(n, speedup(dados, t, per)) for n, t in serie]
    ide = [(n, ideal(dados, t, per)) for n, t in serie]
    vmax = math.ceil(max(v for _, v in ide)) + 1
    el, y = eixo_y(vmax, 1, "Speedup da O2 sobre a O1")
    x0, x1 = M["l"] + 24, W - M["r"] - 24
    lo, hi = math.log10(serie[0][0]), math.log10(serie[-1][0])
    x = lambda n: x0 + (x1 - x0) * (math.log10(n) - lo) / (hi - lo)
    for n, _ in serie:                                  # ticks do eixo log nos tamanhos medidos
        el.append(f'<line x1="{x(n):.1f}" y1="{y(0):.1f}" x2="{x(n):.1f}" y2="{y(0) + 5:.1f}" '
                  f'stroke="{COR["eixo"]}"/>')
        el.append(f'<text x="{x(n):.1f}" y="{y(0) + 18:.1f}" font-size="11" text-anchor="middle" '
                  f'fill="{COR["texto2"]}">{n}</text>')
    el.append(f'<text x="{(x0 + x1) / 2:.0f}" y="{y(0) + 36:.1f}" font-size="11.5" text-anchor="middle" '
              f'fill="{COR["texto2"]}">Instruções úteis no traço (escala logarítmica)</text>')
    # referência ideal: CPI da O1 ÷ 1 de cada traço (tracejado)
    cam_i = " ".join(f"{'M' if i == 0 else 'L'}{x(n):.1f},{y(v):.1f}" for i, (n, v) in enumerate(ide))
    el.append(f'<path d="{cam_i}" fill="none" stroke="{COR["ideal"]}" stroke-width="1.8" stroke-dasharray="6 4"/>')
    el.append(f'<text x="{x(ide[-1][0]):.1f}" y="{y(ide[-1][1]) - 12:.1f}" font-size="11" text-anchor="end" '
              f'fill="{COR["texto2"]}">ideal (CPI da O1 ÷ 1): {num(ide[-1][1])}×</text>')
    el.append(f'<text x="{x(ide[0][0]):.1f}" y="{y(ide[0][1]) - 12:.1f}" font-size="11" text-anchor="start" '
              f'fill="{COR["texto2"]}">ideal: {num(ide[0][1])}×</text>')
    # linha da O2 (2 px) e marcadores com anel da cor do fundo
    caminho = " ".join(f"{'M' if i == 0 else 'L'}{x(n):.1f},{y(v):.1f}" for i, (n, v) in enumerate(pts))
    el.append(f'<path d="{caminho}" fill="none" stroke="{COR["O2"]}" stroke-width="2"/>')
    for n, v in pts:
        el.append(f'<circle cx="{x(n):.1f}" cy="{y(v):.1f}" r="4.5" fill="{COR["O2"]}" '
                  f'stroke="{COR["fundo"]}" stroke-width="2"/>')
    for n, v in (pts[0], pts[-1]):                      # rótulos seletivos: extremos
        el.append(f'<text x="{x(n):.1f}" y="{y(v) + 20:.1f}" font-size="12" font-weight="600" '
                  f'text-anchor="middle" fill="{COR["texto"]}">{num(v)}×</text>')
    el.append(f'<text x="{x(pts[-1][0]) - 10:.1f}" y="{y(pts[-1][1]) + 38:.1f}" font-size="12" '
              f'text-anchor="end" fill="{COR["texto"]}">O2 medido (pipeline)</text>')
    # T0 (32 instruções) como ponto de referência, contorno
    if ("O1", "T0") in dados and ("O2", "T0") in dados:
        n0 = int(dados[("O2", "T0")]["instrucoes"])
        v0 = speedup(dados, "T0", per)
        el.append(f'<circle cx="{x(n0):.1f}" cy="{y(v0):.1f}" r="5" fill="{COR["fundo"]}" '
                  f'stroke="{COR["texto"]}" stroke-width="1.5"/>')
        el.append(f'<text x="{x(n0) + 9:.1f}" y="{y(v0) + 18:.1f}" font-size="11" '
                  f'fill="{COR["texto2"]}">T0 ({n0} instr.): {num(v0)}×</text>')
    with open(saida, "w", encoding="utf-8") as f:
        f.write(svg("Speedup × tamanho do traço",
                    f"série S ({', '.join(str(n) for n, _ in serie)} instruções úteis); "
                    "speedup = tempo O1 / tempo O2; tracejado = ideal",
                    el, f"Fonte: metricas.csv; períodos O1 = {num(per['O1'])} ns e O2 = {num(per['O2'])} ns."))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    dados = ler(sys.argv[1])
    saida = sys.argv[2]
    os.makedirs(saida, exist_ok=True)
    per = {o: float(os.environ.get(f"PERIODO_{o}_NS", "0.22")) for o in ("O1", "O2")}
    grafico_cpi(dados, os.path.join(saida, "cpi_t0.svg"))
    grafico_speedup(dados, per, os.path.join(saida, "speedup_t0.svg"))
    grafico_tamanho(dados, per, os.path.join(saida, "speedup_tamanho.svg"))
    print(f"{saida}: cpi_t0.svg, speedup_t0.svg, speedup_tamanho.svg")


if __name__ == "__main__":
    main()
