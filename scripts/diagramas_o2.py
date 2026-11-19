#!/usr/bin/env python3
"""Diagramas da O2 (seção 6 do enunciado): caminho de dados, unidade de detecção e campos dos
registradores entre estágios, com a largura em bits.

Uso:
    python3 scripts/diagramas_o2.py vhdl docs

Lê vhdl/o1_pkg.vhd, vhdl/o2_pkg.vhd e vhdl/cpu_top_o2.vhd e gera:
    docs/diagramas-o2.md                     texto, tabelas de campos e as duas figuras
    docs/diagramas/o2_caminho_de_dados.svg   caminho de dados com IF/ID, ID/EX, EX/MEM e MEM/WB
    docs/diagramas/o2_unidade_deteccao.svg   blocos, entradas de cada registrador e saídas hazard_*

As larguras vêm dos tipos do pacote (std_logic = 1, word_t = 32, reg_addr_t = 5, enumeração de
N valores = ceil(log2 N) bits). O script falha se um sinal citado nas figuras não existir no
cpu_top_o2.vhd, para o diagrama não divergir do código.
"""
import math
import os
import re
import sys
import textwrap
from html import escape

FONTE = 'font-family="DejaVu Sans, Inter, Arial, sans-serif"'
COR = {"reg": ("#FCE3D6", "#B8421A"), "mem": ("#DCE9FA", "#1F5FB0"), "ula": ("#E4F1E4", "#2E7D32"),
       "ctl": ("#F3ECCB", "#8A6D00"), "box": ("#FFFFFF", "#14213D"), "det": ("#FFF1F0", "#C62828")}
REGS = [("IF/ID", "ifid_t"), ("ID/EX", "idex_t"), ("EX/MEM", "exmem_t"), ("MEM/WB", "memwb_t")]


# --------------------------------------------------------------------------- VHDL
def ler(p):
    return open(p, encoding="utf-8").read()


def tipos(o1, o2):
    larg = {"std_logic": 1}
    for m in re.finditer(r"subtype\s+(\w+)\s+is\s+std_logic_vector\s*\((\d+)\s+downto\s+(\d+)\)", o1, re.I):
        larg[m.group(1).lower()] = int(m.group(2)) - int(m.group(3)) + 1
    for m in re.finditer(r"type\s+(\w+)\s+is\s*\(([^)]*)\)\s*;", o1, re.I):
        n = len([x for x in m.group(2).split(",") if x.strip()])
        larg[m.group(1).lower()] = max(1, math.ceil(math.log2(n)))
    recs = {}
    for m in re.finditer(r"type\s+(\w+)\s+is\s+record(.*?)end\s+record", o2, re.I | re.S):
        campos = []
        for linha in m.group(2).splitlines():
            f = re.match(r"\s*(\w+)\s*:\s*(\w+)\s*;\s*(?:--\s*(.*))?", linha)
            if f:
                campos.append((f.group(1), f.group(2), larg[f.group(2).lower()], (f.group(3) or "").strip()))
        recs[m.group(1).lower()] = campos
    return recs


# --------------------------------------------------------------------------- SVG helpers
class Svg:
    def __init__(self, w, h, titulo):
        self.w, self.h, self.o = w, h, []
        self.o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
                      f'viewBox="0 0 {w} {h}" {FONTE} font-size="15">')
        self.o.append('<defs>'
                      '<marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" '
                      'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#14213D"/></marker>'
                      '<marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" '
                      'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#B8421A"/></marker>'
                      '<marker id="ad" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" '
                      'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#C62828"/></marker>'
                      '</defs>')
        self.o.append(f'<rect width="100%" height="100%" fill="#FFFFFF"/>')
        self.o.append(f'<text x="24" y="30" font-size="21" font-weight="bold" fill="#14213D">{escape(titulo)}</text>')

    def box(self, x, y, w, h, linhas, kind="box", bold=0, fs=15, rx=8, align="middle"):
        fill, stroke = COR[kind]
        self.o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
                      f'stroke="{stroke}" stroke-width="2"/>')
        if isinstance(linhas, str):
            linhas = [linhas]
        lh = fs + 5
        y0 = y + h / 2 - (len(linhas) - 1) * lh / 2 + fs * 0.35
        for i, t in enumerate(linhas):
            peso = ' font-weight="bold"' if i < bold else ""
            tx = x + w / 2 if align == "middle" else x + 12
            self.o.append(f'<text x="{tx}" y="{y0 + i * lh:.1f}" text-anchor="{align}" font-size="{fs}"{peso} '
                          f'fill="#14213D">{escape(t)}</text>')

    def text(self, x, y, t, fs=14, anchor="start", fill="#14213D", bold=False, italic=False):
        extra = (' font-weight="bold"' if bold else "") + (' font-style="italic"' if italic else "")
        self.o.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{fs}" fill="{fill}"{extra}>'
                      f'{escape(t)}</text>')

    def line(self, pts, kind="d", label=None, lpos=None, width=2, dash=None, head=True):
        cor, mk = {"d": ("#14213D", "ah"), "r": ("#B8421A", "ar"), "x": ("#C62828", "ad"),
                   "g": ("#8A8F98", "ah")}[kind]
        d = " ".join(f"{'M' if i == 0 else 'L'}{x},{y}" for i, (x, y) in enumerate(pts))
        da = f' stroke-dasharray="{dash}"' if dash else ""
        mk_attr = f' marker-end="url(#{mk})"' if head else ""
        self.o.append(f'<path d="{d}" fill="none" stroke="{cor}" stroke-width="{width}"{da}{mk_attr}/>')
        if label:
            lx, ly = lpos or ((pts[0][0] + pts[-1][0]) / 2, pts[0][1] - 6)
            self.text(lx, ly, label, fs=13, anchor="middle", fill=cor if kind != "g" else "#555")

    def dot(self, x, y):
        self.o.append(f'<circle cx="{x}" cy="{y}" r="4" fill="#14213D"/>')

    def reg_bar(self, x, y, w, h, nome, bits):
        self.o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{COR["reg"][0]}" '
                      f'stroke="{COR["reg"][1]}" stroke-width="2.5"/>')
        self.o.append(f'<text transform="translate({x + w / 2 + 6},{y + h / 2}) rotate(-90)" text-anchor="middle" '
                      f'font-size="17" font-weight="bold" fill="#B8421A">{nome} · {bits} bits</text>')

    def fim(self):
        self.o.append("</svg>")
        return "\n".join(self.o)


def caixa_campos(s, x, y, w, nome, campos, h=None):
    total = sum(c[2] for c in campos)
    itens = [f"{n} {b}" for n, _, b, _ in campos]
    linhas = textwrap.wrap(" · ".join(itens), width=max(20, int(w / 8.6)))
    h = h or 62 + 21 * len(linhas)
    s.box(x, y, w, h, [], kind="reg")
    s.text(x + 12, y + 26, f"{nome}: {total} bits", fs=17, bold=True, fill="#B8421A")
    for i, l in enumerate(linhas):
        s.text(x + 12, y + 52 + i * 21, l, fs=14)
    return h


# --------------------------------------------------------------------------- caminho de dados
def caminho_de_dados(recs):
    tot = {n: sum(c[2] for c in recs[t]) for n, t in REGS}
    s = Svg(1720, 1040, "Caminho de dados da O2 — pipeline de 5 estágios (sem forwarding, stall nem flush)")
    faixas = [("IF", 30, 330), ("ID", 370, 720), ("EX", 760, 1090), ("MEM", 1130, 1400), ("WB", 1440, 1690)]
    for nome, x0, x1 in faixas:
        s.o.append(f'<rect x="{x0}" y="46" width="{x1 - x0}" height="34" fill="#14213D"/>')
        s.text((x0 + x1) / 2, 69, nome, fs=19, anchor="middle", fill="#FFFFFF", bold=True)
    for nome, x in (("IF/ID", 330), ("ID/EX", 720), ("EX/MEM", 1090), ("MEM/WB", 1400)):
        s.reg_bar(x, 90, 40, 580, nome, tot[nome])

    # ---- IF
    s.box(40, 330, 60, 60, "PC")
    s.box(120, 180, 90, 50, "+ 4")
    s.box(150, 300, 150, 120, ["Memória de", "instruções"], kind="mem", bold=1)
    s.line([(100, 360), (150, 360)])
    s.line([(70, 330), (70, 205), (120, 205)])
    s.line([(210, 205), (235, 205), (235, 140), (24, 140), (24, 360), (40, 360)], label="PC + 4", lpos=(130, 132))
    s.text(30, 118, "sem desvio: um beq tomado aborta (R4)", fs=13, fill="#555", italic=True)
    s.line([(300, 360), (330, 360)], label="instr", lpos=(315, 352))
    s.line([(70, 390), (70, 470), (330, 470)], label="pc", lpos=(200, 462))

    # ---- ID (saídas de IF/ID em x=370, ordenadas por y); componentes em x=440..590
    s.box(440, 110, 150, 80, ["Decodificação", "e controle"], kind="ctl", bold=1)
    s.line([(370, 150), (440, 150)], label="op/funct", lpos=(405, 142), width=1.5)
    s.line([(590, 150), (720, 150)], label="controles", lpos=(655, 142))
    s.box(440, 215, 150, 40, "PC + 4", kind="box")
    s.line([(370, 235), (440, 235)], label="pc", lpos=(405, 227), width=1.5)
    s.line([(590, 235), (720, 235)], label="pc_plus4", lpos=(655, 227))
    s.box(440, 285, 150, 60, ["Extensão de sinal", "16 → 32 bits"], kind="box", fs=14)
    s.line([(370, 315), (440, 315)], label="imm", lpos=(405, 307), width=1.5)
    s.line([(590, 315), (720, 315)], label="imm", lpos=(655, 307))
    s.box(440, 400, 150, 160, ["Banco de", "registradores"], kind="mem", bold=1, fs=14)
    s.text(450, 538, "leitura combinacional", fs=11, fill="#1F5FB0")
    s.text(450, 553, "escrita na descida", fs=11, fill="#1F5FB0")
    s.line([(370, 440), (440, 440)], label="rs", lpos=(405, 432), width=1.5)
    s.line([(370, 510), (440, 510)], label="rt", lpos=(405, 502), width=1.5)
    s.line([(590, 440), (720, 440)], label="rs_value", lpos=(655, 432))
    s.line([(590, 510), (720, 510)], label="rt_value", lpos=(655, 502))

    # ---- EX (saídas de ID/EX em x=760)
    s.box(850, 200, 180, 70, ["alvo do desvio:", "pc_plus4 + (imm << 2)"], kind="ula", fs=13)
    s.line([(760, 235), (850, 235)])
    s.line([(760, 315), (820, 315), (820, 262), (850, 262)], width=2)
    s.line([(820, 315), (820, 540), (845, 540)])
    s.dot(820, 315)
    s.line([(760, 440), (930, 440)])
    s.box(845, 480, 70, 100, ["mux", "use_imm"], kind="box", fs=12)
    s.line([(760, 510), (845, 510)])
    s.line([(915, 530), (930, 530)])
    s.box(930, 400, 100, 160, ["ULA", "(alu_op)"], kind="ula", bold=1)
    s.line([(1030, 480), (1090, 480)])
    s.text(1060, 472, "alu_result", fs=11, anchor="middle")
    s.line([(800, 510), (800, 620), (1090, 620)], label="store_data (rt_value)", lpos=(950, 612))
    s.dot(800, 510)
    s.text(870, 292, "somador de alvo em EX; o PC não é", fs=12, fill="#555", italic=True)
    s.text(870, 308, "redirecionado (aborto por controle)", fs=12, fill="#555", italic=True)

    # ---- MEM (saídas de EX/MEM em x=1130)
    s.box(1180, 400, 130, 170, ["Memória de", "dados"], kind="mem", bold=1, fs=14)
    s.text(1188, 454, "endereço", fs=11, fill="#1F5FB0")
    s.text(1188, 544, "write_data", fs=11, fill="#1F5FB0")
    s.line([(1130, 450), (1180, 450)])
    s.line([(1130, 540), (1180, 540)])
    s.box(1335, 360, 40, 110, ["mux", "is_lw"], kind="box", fs=12)
    s.line([(1130, 300), (1355, 300), (1355, 360)], label="alu_result", lpos=(1240, 292))
    s.line([(1310, 440), (1335, 440)])
    s.line([(1375, 415), (1400, 415)])

    # ---- WB
    s.box(1470, 380, 190, 70, ["Escrita no banco", "wb_enable ∧ valid"], kind="mem", fs=14)
    s.line([(1440, 415), (1470, 415)])
    s.text(1565, 372, "wb_data, wb_addr", fs=12, anchor="middle")
    s.line([(1565, 450), (1565, 700), (495, 700), (495, 560)], kind="r")
    s.text(1555, 692, "escrita na 1ª metade do ciclo (descida)", fs=13, anchor="end", fill="#B8421A")

    # controles que acompanham a instrução
    s.line([(720, 125), (1700, 125)], kind="g", width=1.5, dash="6 5")
    s.text(740, 118, "controles", fs=12, fill="#555", italic=True)
    for i, t in enumerate(("valid e os controles (is_lw, is_sw,", "is_beq, is_break, wb_enable, wb_addr)",
                           "acompanham a instrução até WB", "(linha tracejada cinza).", "",
                           "Distância 3: o banco escreve", "antes de a consumidora ler.")):
        s.text(30, 590 + i * 17, t, fs=12, fill="#555", italic=True)

    # ---- unidade de detecção
    s.box(560, 745, 700, 80, ["Unidade de detecção de conflitos (hazard_*)", "dados · estrutural · controle → aborto"],
          kind="det", bold=1, fs=16)
    s.line([(350, 670), (350, 785), (560, 785)], kind="x", width=1.5, dash="5 4")
    s.line([(740, 670), (740, 745)], kind="x", width=1.5, dash="5 4")
    s.line([(1110, 670), (1110, 745)], kind="x", width=1.5, dash="5 4")
    s.line([(1010, 560), (1010, 745)], kind="x", width=1.5, dash="5 4", label="zero", lpos=(1024, 650))
    s.line([(1260, 785), (1330, 785)], kind="x", label="", width=2)
    s.text(1338, 775, "hazard_abort", fs=14, bold=True, fill="#C62828")
    s.text(1338, 793, "hazard_type · hazard_pc · hazard_cycle", fs=13, fill="#C62828")
    s.text(560, 845, "frozen: congela PC, registradores entre estágios, banco e memória até o reset",
           fs=13, fill="#C62828", italic=True)

    # ---- campos
    s.text(30, 882, "Campos dos registradores entre estágios (largura em bits, lida de vhdl/o2_pkg.vhd)", fs=17, bold=True)
    x, ys = 30, 898
    for (nome, t), w in zip(REGS, (390, 440, 390, 390)):
        caixa_campos(s, x, ys, w, nome, recs[t], h=118)
        x += w + 20
    return s.fim()


# --------------------------------------------------------------------------- unidade de detecção
def unidade_deteccao(recs):
    s = Svg(1600, 880, "Unidade de detecção de conflitos da O2 — entradas, blocos e saídas")
    s.text(30, 62, "Entradas (registradores entre estágios)", fs=16, bold=True)
    s.box(30, 75, 330, 135, ["IF/ID", "valid · instr[31:26] opcode", "instr[25:21] = rs · instr[20:16] = rt"], kind="reg", bold=1, fs=14)
    s.box(30, 230, 330, 110, ["ID/EX", "valid · wb_enable · wb_addr[4:0]", "is_beq"], kind="reg", bold=1, fs=14)
    s.box(30, 360, 330, 130, ["EX/MEM", "valid · wb_enable · wb_addr[4:0]", "is_lw · is_sw"], kind="reg", bold=1, fs=14)
    s.box(30, 510, 330, 70, ["ULA (estágio EX)", "alu_zero  (rs − rt = 0)"], kind="ula", bold=1, fs=14)
    s.box(30, 600, 330, 120, ["IF (busca)", "fetch_valid_now = stream_active ∧ ¬frozen", "∧ ¬(break em ID) · generic MEM_UNIFICADA"], kind="box", bold=1, fs=14)

    X0, X1 = 560, 980
    s.box(X0, 75, X1 - X0, 120, ["Uso de operandos: id_uses_rs / id_uses_rt", "tipo R (≠ break): rs e rt",
                                  "addi, lw: só rs · sw, beq: rs e rt"], kind="ctl", bold=1, fs=14)
    s.box(X0, 215, X1 - X0, 230, ["Conflito de DADOS (tipo 01)",
                                   "hit: produtora válida (wb_enable = 1,",
                                   "wb_addr ≠ $zero) em distância 1 (ID/EX) ou",
                                   "distância 2 (EX/MEM) e (usa rs ∧ rs = wb_addr)",
                                   "ou (usa rt ∧ rt = wb_addr)",
                                   "data_conflict = hit ∧ ¬frozen ∧ ¬branch_taken"], kind="det", bold=1, fs=14)
    s.box(X0, 465, X1 - X0, 100, ["Conflito ESTRUTURAL (tipo 10)",
                                   "MEM_UNIFICADA ∧ fetch_valid_now ∧",
                                   "EX/MEM.valid ∧ (is_lw ∨ is_sw)  →  structural_conflict"], kind="det", bold=1, fs=14)
    s.box(X0, 585, X1 - X0, 160, ["Conflito de CONTROLE (tipo 11)",
                                   "branch_taken = ID/EX.valid ∧ is_beq ∧ alu_zero",
                                   "control_conflict = branch_taken ∧ ¬frozen ∧",
                                   "(IF/ID.valid ∨ fetch_valid_now)",
                                   "branch_pc = pc_plus4 − 4"], kind="det", bold=1, fs=14)
    s.line([(750, 195), (750, 215)], label="usa rs/rt", lpos=(796, 210))

    # barramentos: uma faixa vertical por origem; derivações com ponto
    def faixa(x, saida, derivacoes):
        ys = [saida] + [y for y, _ in derivacoes]
        s.line([(360, saida), (x, saida)], head=False, width=1.8)
        s.line([(x, min(ys)), (x, max(ys))], head=False, width=1.8)
        for y, rot in derivacoes:
            s.line([(x, y), (X0, y)], width=1.5, label=rot, lpos=((x + X0) / 2, y - 5))
            s.dot(x, y)
    faixa(380, 145, [(120, "opcode"), (250, "rs, rt"), (610, "valid")])
    faixa(400, 285, [(300, "dist. 1"), (640, "valid, is_beq")])
    faixa(420, 425, [(350, "dist. 2"), (495, "valid, lw/sw")])
    faixa(440, 545, [(670, "zero")])
    faixa(460, 660, [(535, "fetch_valid_now"), (700, "fetch_valid_now")])

    # prioridade e aborto
    PX0, PX1 = 1100, 1280
    s.box(PX0, 215, PX1 - PX0, 530, ["Prioridade", "e aborto", "", "controle (EX)", "> dados (ID)", "> estrutural (IF)", "",
                                      "frozen ← 1", "hazard_type_reg", "hazard_pc_reg", "cycle_cnt"], kind="det", bold=2, fs=14)
    for y in (330, 515, 665):
        s.line([(X1, y), (PX0, y)], kind="x", width=2)
    s.text(X1 + 60, 322, "data_conflict", fs=11, anchor="middle", fill="#C62828")
    s.text(X1 + 60, 507, "structural_conflict", fs=11, anchor="middle", fill="#C62828")
    s.text(X1 + 60, 657, "control_conflict", fs=11, anchor="middle", fill="#C62828")

    # saídas
    s.text(1340, 210, "Saídas (R3)", fs=16, bold=True)
    for i, (t, sub) in enumerate((("hazard_abort", "1 bit"), ("hazard_type", "2 bits: 01 · 10 · 11"),
                                  ("hazard_pc", "32 bits"), ("hazard_cycle", "32 bits"))):
        y = 235 + i * 110
        s.box(1340, y, 200, 80, [t, sub], kind="box", bold=1, fs=14)
        s.line([(PX1, y + 40), (1340, y + 40)], kind="x", width=2)
    s.text(1340, 690, "hazard_pc: a consumidora (dados), a", fs=12, fill="#555", italic=True)
    s.text(1340, 707, "instrução em IF (estrutural) ou o beq", fs=12, fill="#555", italic=True)
    s.text(1340, 724, "(controle).", fs=12, fill="#555", italic=True)

    s.text(1340, 745, "hazard_cycle = cycle_cnt + 1 até congelar.", fs=12, fill="#555", italic=True)
    # congelamento
    s.box(X0, 790, PX1 - X0, 60, ["frozen = 1: PC, registradores entre estágios, banco de registradores e",
                                    "memória param; hazard_* ficam estáveis até o reset"], kind="det", fs=14)
    s.line([(1190, 745), (1190, 790)], kind="x", dash="7 5", width=1.8)
    return s.fim()


# --------------------------------------------------------------------------- doc
SINAIS = ["data_conflict", "structural_conflict", "control_conflict", "branch_taken", "branch_pc",
          "id_uses_rs", "id_uses_rt", "fetch_valid_now", "frozen", "hazard_type_reg", "hazard_pc_reg",
          "stream_active", "cycle_cnt", "alu_zero", "wb_write_en", "idex_next", "mem_read_en", "mem_write_en",
          "MEM_UNIFICADA"]


def conferir_sinais(cpu):
    falta = [n for n in SINAIS if not re.search(rf"\b{n}\b", cpu)]
    if falta:
        sys.exit(f"sinais citados nos diagramas que não existem em cpu_top_o2.vhd: {falta}")


def documento(recs):
    nomes = {t: n for n, t in REGS}
    campos_todos = []
    for _, t in REGS:
        for c in recs[t]:
            if c[0] not in campos_todos:
                campos_todos.append(c[0])
    o = ["# Diagramas da O2: caminho de dados, unidade de detecção e registradores entre estágios", "",
         "Gerados por `scripts/diagramas_o2.py` (`make diagramas-o2`) a partir de `vhdl/o2_pkg.vhd` e "
         "`vhdl/cpu_top_o2.vhd`: as larguras vêm dos tipos do pacote e o script falha se um sinal citado nas "
         "figuras não existir no código. Para a O1, o caminho de dados está em [`fsm-o1.md`](fsm-o1.md).", "",
         "## 1. Caminho de dados da O2", "",
         "![Caminho de dados da O2](diagramas/o2_caminho_de_dados.svg)", "",
         "- **IF:** o PC endereça a memória de instruções e alimenta um somador `+4`; `instr` e `pc` entram em IF/ID.",
         "- **ID:** decodificação e controle (`idex_next`), leitura combinacional de `rs` e `rt`, extensão de "
         "sinal do imediato e `pc_plus4`; tudo entra em ID/EX.",
         "- **EX:** a ULA opera `rs_value` com `rt_value` ou `imm` (mux `use_imm`); o somador calcula "
         "`pc_plus4 + (imm << 2)`. O `zero` da ULA vai para a detecção. O resultado e o `store_data` entram em EX/MEM.",
         "- **MEM:** a memória de dados é acessada com `alu_result` (endereço) e `store_data`; um mux escolhe "
         "`mem_data` (lw) ou `alu_result` e grava `wb_data` em MEM/WB.",
         "- **WB:** o banco é escrito com `wb_data` em `wb_addr`, quando `valid ∧ wb_enable`, **na 1ª metade do "
         "ciclo** (borda de descida); por isso uma consumidora em ID a distância 3 já lê o valor novo.",
         "- Os controles (`is_lw`, `is_sw`, `wb_enable`, `wb_addr`, `is_break`) e o bit `valid` acompanham a "
         "instrução de registrador em registrador.", "",
         "## 2. Unidade de detecção de conflitos", "",
         "![Unidade de detecção da O2](diagramas/o2_unidade_deteccao.svg)", "",
         "| Conflito | Condição (sinais do `cpu_top_o2.vhd`) | `hazard_type` | `hazard_pc` |",
         "| --- | --- | :---: | --- |",
         "| Dados | `id_uses_rs/rt` casa com `wb_addr` de produtora válida, `wb_enable = 1`, destino ≠ `$zero`, em ID/EX (distância 1) ou EX/MEM (distância 2) | `01` | a consumidora (ID) |",
         "| Estrutural | `MEM_UNIFICADA ∧ fetch_valid_now ∧ EX/MEM.valid ∧ (is_lw ∨ is_sw)` | `10` | a instrução em IF (a mais nova) |",
         "| Controle | `branch_taken` (`ID/EX.valid ∧ is_beq ∧ alu_zero`) com instrução já buscada em ID ou IF | `11` | o `beq` (`pc_plus4 − 4`) |", "",
         "Quando mais de um conflito ocorre no mesmo ciclo, vale o da instrução mais antiga: controle > dados > "
         "estrutural. No ciclo da detecção `hazard_abort`, `hazard_type` e `hazard_pc` são combinacionais; na "
         "borda seguinte `frozen` vira 1 e tipo e PC são gravados em `hazard_type_reg` e `hazard_pc_reg`. "
         "`hazard_cycle` usa a convenção do `tb_cpu` (ciclo 1 = primeiro após o reset). As waveforms de "
         "detecção de cada traço estão em [`waveforms-aborto.md`](waveforms-aborto.md).", "",
         "## 3. Registradores entre estágios: campos e larguras", "",
         "Larguras em bits, lidas de `vhdl/o2_pkg.vhd`: `std_logic` = 1, `word_t` = 32, `reg_addr_t` = 5, "
         "`alu_operation_t` (5 operações) = 3.", ""]
    for nome, t in REGS:
        tot = sum(c[2] for c in recs[t])
        o += [f"### {nome} ({tot} bits)", "", "| Campo | Tipo VHDL | Bits | Descrição |", "| --- | --- | ---: | --- |"]
        for n, ty, b, com in recs[t]:
            o.append(f"| `{n}` | `{ty}` | {b} | {com or '—'} |")
        o += [f"| **Total** | | **{tot}** | |", ""]
    o += ["### Quais campos acompanham a instrução", "",
          "| Campo | " + " | ".join(n for n, _ in REGS) + " |", "| --- |" + " :---: |" * len(REGS)]
    for c in campos_todos:
        marc = ["✓" if any(x[0] == c for x in recs[t]) else "" for _, t in REGS]
        o.append(f"| `{c}` | " + " | ".join(marc) + " |")
    o += ["", "Cada campo só segue adiante enquanto algum estágio posterior precisa dele: `store_data` termina em "
          "MEM, `imm` e `rs_value`/`rt_value` terminam em EX; `valid`, `wb_enable`, `wb_addr` e `is_break` chegam "
          "até WB. EX/MEM e MEM/WB não carregam o PC: nenhuma lógica posterior o usa.", ""]
    return "\n".join(o)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    vhdl, docs = sys.argv[1:]
    o1, o2, cpu = (ler(f"{vhdl}/{n}") for n in ("o1_pkg.vhd", "o2_pkg.vhd", "cpu_top_o2.vhd"))
    recs = tipos(o1, o2)
    for _, t in REGS:
        if t not in recs:
            sys.exit(f"record {t} não encontrado em o2_pkg.vhd")
    conferir_sinais(cpu)
    os.makedirs(f"{docs}/diagramas", exist_ok=True)
    open(f"{docs}/diagramas/o2_caminho_de_dados.svg", "w", encoding="utf-8").write(caminho_de_dados(recs))
    open(f"{docs}/diagramas/o2_unidade_deteccao.svg", "w", encoding="utf-8").write(unidade_deteccao(recs))
    open(f"{docs}/diagramas-o2.md", "w", encoding="utf-8").write(documento(recs))
    print("larguras: " + ", ".join(f"{n} = {sum(c[2] for c in recs[t])} bits" for n, t in REGS))


if __name__ == "__main__":
    main()
