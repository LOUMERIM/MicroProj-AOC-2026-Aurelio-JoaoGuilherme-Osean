#!/usr/bin/env python3
"""Waveform de detecção e aborto de um traço de conflito na O2 (seção 6 do enunciado).

Uso:
    python3 scripts/waveform_aborto.py build/td_o2.ghw tracos/td.asm docs/waveforms td dados

O último argumento é o tipo de conflito: dados | estrutural | controle.

Lê o dump GHW da simulação (ghwdump), amostra cada ciclo na borda de descida (convenção do
tb_cpu: ciclo 1 = primeiro ciclo após o reset) e, de C1 até 4 ciclos depois do aborto, gera:
    <nome>_aborto.svg    sinais agrupados por estágio, com os campos que disparam a detecção,
                         hazard_abort, o congelamento do PC e marcadores no ciclo exato
    <nome>_aborto.csv    os mesmos valores, ciclo a ciclo
    <nome>_aborto.gtkw   sessão do GTKWave (abrir com build/<nome>_o2.ghw)

Confere a simulação: a detecção reproduzida a partir dos campos amostrados tem de coincidir com
o sinal do hardware (data/structural/control_conflict), e hazard_*, o PC e os estágios têm de
ficar estáveis depois do aborto. O texto dos marcadores é montado dos valores amostrados.
"""
import csv
import os
import sys
from html import escape

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gerar_serie_s import NOMES  # noqa: E402
from waveform_o2 import Signals, sample_cycles, load_asm  # noqa: E402

D = "/tb_cpu/gen_o2/dut/"
T = "/tb_cpu/"
NOME = {v: f"${k}" for k, v in reversed(list(NOMES.items()))}
TIPO_COD = {"dados": "01", "estrutural": "10", "controle": "11"}
VERM, AZUL, CINZA, ESC = "#C62828", "#1F5FB0", "#9CA3AF", "#14213D"


# --------------------------------------------------------------------------- amostragem
def coletar(sig, asm):
    snaps = sample_cycles(sig)
    tempos = sample_cycles.times
    linhas = []
    for k, s in enumerate(snaps, start=1):
        b = lambda path, f=None: sig.bits(s, path, f)
        n = lambda path, f=None: sig.num(s, path, f)
        p4 = n(D + "idex_reg", "pc_plus4")
        instr = n(D + "ifid_reg", "instr")
        r = {
            "ciclo": k, "t": tempos[k - 1],
            "if_pc": n(D + "pc"), "if_v": int(b(D + "fetch_valid_now")),
            "id_v": int(b(D + "ifid_reg", "valid")), "id_pc": n(D + "ifid_reg", "pc"), "id_instr": instr,
            "rs": (instr >> 21) & 31 if instr is not None else None,
            "rt": (instr >> 16) & 31 if instr is not None else None,
            "usa_rs": int(b(D + "id_uses_rs")), "usa_rt": int(b(D + "id_uses_rt")),
            "ex_v": int(b(D + "idex_reg", "valid")), "ex_pc": (p4 - 4) & 0xFFFFFFFF if p4 is not None else None,
            "ex_we": int(b(D + "idex_reg", "wb_enable")), "ex_wa": n(D + "idex_reg", "wb_addr"),
            "ex_beq": int(b(D + "idex_reg", "is_beq")),
            "mem_v": int(b(D + "exmem_reg", "valid")), "mem_we": int(b(D + "exmem_reg", "wb_enable")),
            "mem_wa": n(D + "exmem_reg", "wb_addr"), "mem_lw": int(b(D + "exmem_reg", "is_lw")),
            "mem_sw": int(b(D + "exmem_reg", "is_sw")),
            "zero": int(b(D + "alu_zero")), "bt": int(b(D + "branch_taken")),
            "c_dados": int(b(D + "data_conflict")), "c_estr": int(b(D + "structural_conflict")),
            "c_ctrl": int(b(D + "control_conflict")),
            "frozen": int(b(D + "frozen")), "abort": int(b(T + "hazard_abort")),
            "tipo": b(T + "hazard_type"), "hpc": n(T + "hazard_pc"), "hciclo": n(T + "hazard_cycle"),
            "ret": n(T + "retired"), "sv": int(b(T + "stage_valid")[-5:], 2),
        }
        if not r["ex_v"]:
            r["ex_pc"] = None
        if not r["id_v"]:
            r["id_pc"] = None
        linhas.append(r)
    A = next(r["ciclo"] for r in linhas if r["abort"])
    linhas = [r for r in linhas if r["ciclo"] <= A + 4]
    # PC de MEM: o de EX um ciclo antes, enquanto o pipeline avança (não avança com aborto)
    for i, r in enumerate(linhas):
        if i == 0:
            r["mem_pc"] = None
        else:
            ant = linhas[i - 1]
            r["mem_pc"] = ant["mem_pc"] if ant["abort"] else ant["ex_pc"]
    return linhas, A


def curto(texto):
    """Nome curto do marcador no GTKWave."""
    for chave, nome in (("é buscad", "instrucao-causa em IF"), ("NÃO tomado", "beq nao tomado: sem conflito"),
                        ("hazard_abort = 1", "deteccao: hazard_abort = 1"), ("frozen = 1.", "frozen = 1: PC congelado"),
                        ("continuam estáveis", "hazard_* estaveis")):
        if chave in texto:
            return nome
    return "marcador"


def hx(v, w=2):
    return "—" if v is None else f"0x{v:0{w}X}"


def reg(v):
    return "—" if v is None else NOME.get(v, f"x{v}")


def instr_txt(asm, pc):
    return asm.get(pc, "?") if pc is not None else "—"


# --------------------------------------------------------------------------- conferências
def conferir(linhas, A, tipo_cod, tipo):
    r = linhas[A - 1]
    assert r["tipo"] == tipo_cod, f"hazard_type {r['tipo']} != {tipo_cod}"
    assert r["hciclo"] == A, f"hazard_cycle {r['hciclo']} != {A}"
    # a detecção reproduzida dos campos tem de coincidir com o sinal do hardware
    for x in linhas[:A]:
        hit = False
        for v, we, wa in ((x["ex_v"], x["ex_we"], x["ex_wa"]), (x["mem_v"], x["mem_we"], x["mem_wa"])):
            if v and we and wa not in (0, None):
                hit |= bool((x["usa_rs"] and x["rs"] == wa) or (x["usa_rt"] and x["rt"] == wa))
        bt = int(x["ex_v"] and x["ex_beq"] and x["zero"])
        ctrl = int(bt and (x["id_v"] or x["if_v"]))
        estr = int(x["if_v"] and x["mem_v"] and (x["mem_lw"] or x["mem_sw"]) and tipo == "estrutural")
        if ctrl:
            assert x["c_ctrl"] == 1 and x["bt"] == 1, f"C{x['ciclo']}: controle não bate"
        else:
            assert x["c_ctrl"] == 0, f"C{x['ciclo']}: control_conflict inesperado"
            if hit and not bt:
                assert x["c_dados"] == 1, f"C{x['ciclo']}: dados não bate"
            else:
                assert x["c_dados"] == 0, f"C{x['ciclo']}: data_conflict inesperado"
                if estr:
                    assert x["c_estr"] == 1, f"C{x['ciclo']}: estrutural não bate"
                else:
                    assert x["c_estr"] == 0, f"C{x['ciclo']}: structural_conflict inesperado"
    # estabilidade depois do aborto
    for x in linhas[A:]:
        assert x["abort"] == 1 and x["frozen"] == 1, f"C{x['ciclo']}: não congelou"
        for c in ("tipo", "hpc", "hciclo", "if_pc", "sv", "id_pc", "ex_pc", "mem_pc"):
            assert x[c] == r[c] or c in ("mem_pc",), f"C{x['ciclo']}: {c} mudou depois do aborto"
        assert x["ret"] == 0, f"C{x['ciclo']}: retired ≠ 0 depois do aborto"


# --------------------------------------------------------------------------- linhas do desenho
def spec(tipo, asm):
    pcs = lambda k: (lambda r: hx(r[k]))
    ins = lambda k: (lambda r: instr_txt(asm, r[k]))
    saidas = [("Saídas R3 e congelamento", [
        ("hazard_abort", "bit", lambda r: r["abort"], True),
        ("frozen (DUT)", "bit", lambda r: r["frozen"], False),
        ("hazard_type", "bus", lambda r: r["tipo"], False),
        ("hazard_pc", "bus", lambda r: hx(r["hpc"], 8), False),
        ("hazard_cycle", "bus", lambda r: str(r["hciclo"]), False),
        ("stage_valid[4:0]", "bus", lambda r: hx(r["sv"]), False),
        ("retired", "bus", lambda r: str(r["ret"]), False)])]
    pc_if = ("IF", [("PC (IF)", "bus", pcs("if_pc"), False)])
    if tipo == "dados":
        corpo = [
            ("IF", [("PC (IF)", "bus", pcs("if_pc"), False)]),
            ("ID — consumidora", [
                ("ID válido", "bit", lambda r: r["id_v"], False),
                ("ID instrução", "bus", lambda r: instr_txt(asm, r["id_pc"]) if r["id_v"] else "—", False),
                ("ID lê rs", "bus", lambda r: reg(r["rs"]) if r["id_v"] and r["usa_rs"] else "—", False),
                ("ID lê rt", "bus", lambda r: reg(r["rt"]) if r["id_v"] and r["usa_rt"] else "—", False)]),
            ("EX — produtora a distância 1", [
                ("EX válido", "bit", lambda r: r["ex_v"], False),
                ("EX instrução", "bus", lambda r: instr_txt(asm, r["ex_pc"]) if r["ex_v"] else "—", False),
                ("EX escreve", "bus", lambda r: (reg(r["ex_wa"]) if r["ex_wa"] else "$zero (ignora)") if r["ex_v"] and r["ex_we"] else "—", False)]),
            ("MEM — produtora a distância 2", [
                ("MEM válido", "bit", lambda r: r["mem_v"], False),
                ("MEM escreve", "bus", lambda r: (reg(r["mem_wa"]) if r["mem_wa"] else "$zero (ignora)") if r["mem_v"] and r["mem_we"] else "—", False)]),
            ("Detecção", [("data_conflict", "bit", lambda r: r["c_dados"], True)])]
    elif tipo == "estrutural":
        corpo = [
            ("IF", [("PC (IF)", "bus", pcs("if_pc"), False),
                    ("IF busca (fetch_valid_now)", "bit", lambda r: r["if_v"], False)]),
            ("MEM — usa a mesma memória", [
                ("MEM válido", "bit", lambda r: r["mem_v"], False),
                ("MEM instrução", "bus", lambda r: instr_txt(asm, r["mem_pc"]) if r["mem_v"] else "—", False),
                ("MEM é lw ou sw", "bit", lambda r: int(r["mem_lw"] or r["mem_sw"]), False)]),
            ("Detecção", [("structural_conflict", "bit", lambda r: r["c_estr"], True)])]
    else:
        corpo = [
            ("IF", [("PC (IF)", "bus", pcs("if_pc"), False),
                    ("IF busca (fetch_valid_now)", "bit", lambda r: r["if_v"], False)]),
            ("ID", [("ID válido", "bit", lambda r: r["id_v"], False),
                    ("ID instrução", "bus", lambda r: instr_txt(asm, r["id_pc"]) if r["id_v"] else "—", False)]),
            ("EX — desvio resolvido em EX", [
                ("EX válido", "bit", lambda r: r["ex_v"], False),
                ("EX instrução", "bus", lambda r: instr_txt(asm, r["ex_pc"]) if r["ex_v"] else "—", False),
                ("EX é beq", "bit", lambda r: r["ex_beq"], False),
                ("zero (ULA)", "bit", lambda r: r["zero"], False),
                ("branch_taken", "bit", lambda r: r["bt"], False)]),
            ("Detecção", [("control_conflict", "bit", lambda r: r["c_ctrl"], True)])]
    return corpo + saidas


def marcadores(tipo, linhas, A, asm):
    r = linhas[A - 1]
    f = lambda k: instr_txt(asm, r[k])
    sufixo = (f"hazard_abort = 1, hazard_type = {r['tipo']}, hazard_pc = {hx(r['hpc'], 8)}, "
              f"hazard_cycle = {r['hciclo']} (combinacionais neste ciclo).")
    if tipo == "dados":
        causas = []
        for nome, v, we, wa, pc, dist in (("EX", r["ex_v"], r["ex_we"], r["ex_wa"], r["ex_pc"], 1),
                                          ("MEM", r["mem_v"], r["mem_we"], r["mem_wa"], r["mem_pc"], 2)):
            if v and we and wa:
                for lado, usa, val in (("rs", r["usa_rs"], r["rs"]), ("rt", r["usa_rt"], r["rt"])):
                    if usa and val == wa:
                        causas.append(f"lê {reg(wa)} ({lado}), que {instr_txt(asm, pc)} ({hx(pc)}) escreve em {nome} "
                                      f"(distância {dist})")
        det = (f"{f('id_pc')} ({hx(r['id_pc'])}) em ID " + "; e ".join(causas) +
               f". data_conflict = 1, {sufixo}")
        antes = next((x for x in linhas[:A] if x["if_v"] and x["if_pc"] == r["id_pc"]), None)
        m0 = (antes["ciclo"], f"C{antes['ciclo']}: a consumidora {f('id_pc')} ({hx(r['id_pc'])}) é buscada em IF.") if antes else None
    elif tipo == "estrutural":
        det = (f"{instr_txt(asm, r['mem_pc'])} ({hx(r['mem_pc'])}) em MEM usa a memória e IF busca {hx(r['if_pc'])} "
               f"({instr_txt(asm, r['if_pc'])}) na mesma memória. structural_conflict = 1, {sufixo}")
        m0 = None
    else:
        det = (f"{f('ex_pc')} ({hx(r['ex_pc'])}) em EX com zero = 1: desvio tomado; ID tem {hx(r['id_pc'])} e IF busca "
               f"{hx(r['if_pc'])}. control_conflict = 1, {sufixo}")
        antes = next((x for x in linhas[:A] if x["if_v"] and x["if_pc"] == r["ex_pc"]), None)
        m0 = (antes["ciclo"], f"C{antes['ciclo']}: o desvio {f('ex_pc')} ({hx(r['ex_pc'])}) é buscado em IF.") if antes else None
    out = []
    if m0:
        out.append(m0)
    if tipo == "controle":
        nt = next((x for x in linhas[:A - 1] if x["ex_v"] and x["ex_beq"] and not x["zero"]), None)
        if nt:
            out.append((nt["ciclo"], f"C{nt['ciclo']}: {instr_txt(asm, nt['ex_pc'])} ({hx(nt['ex_pc'])}) em EX com zero = 0: "
                                     "desvio NÃO tomado, então não é conflito (control_conflict = 0) e o pipeline segue."))
    out.sort(key=lambda m: m[0])
    out.append((A, f"C{A}: {det}"))
    c1 = linhas[A]
    out.append((A + 1, f"C{A + 1}: frozen = 1. O PC de IF fica em {hx(c1['if_pc'])}, o mesmo de C{A}: o PC e os estágios "
                       "congelaram na borda que encerrou a detecção."))
    out.append((A + 4, f"C{A + 4}: hazard_type = {r['tipo']}, hazard_pc = {hx(r['hpc'], 8)} e hazard_cycle = {r['hciclo']} "
                       "continuam estáveis; retired = 0. Só um reset limpa o estado."))
    return out


# --------------------------------------------------------------------------- SVG
def desenhar(titulo, linhas, A, rows, marks, tipo):
    lab_w, colw, row_h, top = 230, 112, 27, 110
    n = len(linhas)
    n_lin = sum(len(g[1]) + 1 for g in rows) + 2
    leg_h = 22 * (len(marks) + 3)
    W = lab_w + colw * n + 24
    H = top + n_lin * row_h + 24 + leg_h + 34
    x = lambda c: lab_w + (c - 1) * colw
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
         f'font-family="DejaVu Sans, Inter, Arial, sans-serif" font-size="12">',
         '<rect width="100%" height="100%" fill="#FFFFFF"/>',
         f'<text x="12" y="24" font-size="17" font-weight="bold" fill="{ESC}">{escape(titulo)}</text>',
         f'<text x="12" y="44" font-size="12.5" fill="#4A5568">Ciclo 1 = primeiro ciclo após o reset (borda de descida, '
         f'convenção do tb_cpu). Hexadecimal; — = estágio sem instrução válida (bolha). hazard_type/pc/cycle só valem com hazard_abort = 1.</text>']
    # colunas especiais
    o.append(f'<rect x="{x(A)}" y="{top - 28}" width="{colw}" height="{n_lin * row_h + 28}" fill="#FDE2E2"/>')
    o.append(f'<rect x="{x(A + 1)}" y="{top - 28}" width="{colw * (n - A)}" height="{n_lin * row_h + 28}" fill="#E3EEFB"/>')
    o.append(f'<text x="{x(A) + colw / 2}" y="{top - 36}" text-anchor="middle" font-weight="bold" fill="{VERM}">detecção</text>')
    o.append(f'<text x="{x(A + 1) + colw * (n - A) / 2}" y="{top - 36}" text-anchor="middle" font-weight="bold" '
             f'fill="{AZUL}">congelado</text>')
    for r in linhas:
        c = r["ciclo"]
        o.append(f'<text x="{x(c) + colw / 2}" y="{top - 12}" text-anchor="middle" font-weight="bold" fill="{ESC}">C{c}</text>')
        o.append(f'<line x1="{x(c)}" y1="{top - 28}" x2="{x(c)}" y2="{top + n_lin * row_h}" stroke="#E5E7EB"/>')
    # relógio
    y = top
    o.append(f'<text x="8" y="{y + 17}" font-weight="bold" fill="#374151">Relógio</text>')
    o.append(f'<line x1="0" y1="{y + 1}" x2="{W}" y2="{y + 1}" stroke="{CINZA}"/>')
    y += row_h
    o.append(f'<text x="18" y="{y + 17}">clk</text>')
    hi, lo = y + 5, y + row_h - 5
    for r in linhas:
        xa = x(r["ciclo"])
        o.append(f'<polyline fill="none" stroke="{ESC}" points="{xa},{lo} {xa},{hi} {xa + colw / 2},{hi} '
                 f'{xa + colw / 2},{lo} {xa + colw},{lo}"/>')
    y += row_h
    # grupos
    for gnome, itens in rows:
        o.append(f'<text x="8" y="{y + 17}" font-weight="bold" fill="#374151">{escape(gnome)}</text>')
        o.append(f'<line x1="0" y1="{y + 1}" x2="{W}" y2="{y + 1}" stroke="{CINZA}"/>')
        y += row_h
        for label, kind, get, crit in itens:
            cor = VERM if crit else ESC
            o.append(f'<text x="18" y="{y + 17}" fill="{VERM if crit else ESC}"{" font-weight=" + chr(34) + "bold" + chr(34) if crit else ""}>{escape(label)}</text>')
            hi, lo = y + 5, y + row_h - 5
            for i, r in enumerate(linhas):
                xa, xb = x(r["ciclo"]), x(r["ciclo"]) + colw
                v = get(r)
                if kind == "bit":
                    yy = hi if v else lo
                    o.append(f'<line x1="{xa}" y1="{yy}" x2="{xb}" y2="{yy}" stroke="{cor}" stroke-width="2.4"/>')
                    if i > 0 and get(linhas[i - 1]) != v:
                        o.append(f'<line x1="{xa}" y1="{hi}" x2="{xa}" y2="{lo}" stroke="{cor}" stroke-width="2.4"/>')
                else:
                    vazio = v in ("—", None)
                    c = CINZA if vazio else (VERM if crit else "#1E3A8A")
                    d = 5
                    o.append(f'<polygon fill="{"#F3F4F6" if vazio else "#EEF2FF"}" stroke="{c}" points="{xa + d},{hi} {xb - d},{hi} '
                             f'{xb},{y + row_h / 2} {xb - d},{lo} {xa + d},{lo} {xa},{y + row_h / 2}"/>')
                    t = str(v)
                    fs = 10.5 if len(t) > 14 else 12
                    o.append(f'<text x="{(xa + xb) / 2}" y="{y + row_h / 2 + 4}" text-anchor="middle" font-size="{fs}" fill="{c}">{escape(t)}</text>')
            y += row_h
    # marcadores
    yb = top + n_lin * row_h + 30
    for i, (c, t) in enumerate(marks, start=1):
        xc = x(c) + colw / 2
        o.append(f'<circle cx="{xc}" cy="{top - 58}" r="9" fill="{VERM}"/>')
        o.append(f'<text x="{xc}" y="{top - 54}" text-anchor="middle" fill="#FFFFFF" font-size="11" font-weight="bold">{i}</text>')
        o.append(f'<line x1="{xc}" y1="{top - 49}" x2="{xc}" y2="{top - 40}" stroke="{VERM}"/>')
    for i, (c, t) in enumerate(marks, start=1):
        lines = []
        palavras, atual = t.split(" "), ""
        for pl in palavras:
            if len(atual) + len(pl) + 1 > 190:
                lines.append(atual)
                atual = pl
            else:
                atual = (atual + " " + pl).strip()
        lines.append(atual)
        o.append(f'<text x="12" y="{yb}" fill="{VERM}">({i}) {escape(lines[0])}</text>')
        for extra in lines[1:]:
            yb += 17
            o.append(f'<text x="34" y="{yb}" fill="{VERM}">{escape(extra)}</text>')
        yb += 20
    o.append("</svg>")
    return "\n".join(o)


# --------------------------------------------------------------------------- gtkwave
def bus(nome, path, msb, lsb=0):
    return "#{" + nome + "} " + " ".join(f"{path}[{i}]" for i in range(msb, lsb - 1, -1))


def gtkw(linhas, A, tipo, dump, marks):
    d = "top.tb_cpu.gen_o2.dut."
    t = {r["ciclo"]: r["t"] for r in linhas}
    per = linhas[1]["t"] - linhas[0]["t"]
    grupos = [("Relogio", [("28", "+{clk} top.tb_cpu.clk")]),
              ("IF", [("22", bus("IF PC", d + "pc", 31)), ("28", "+{IF busca} " + d + "fetch_valid_now")])]
    if tipo == "dados":
        grupos += [("ID consumidora", [("28", "+{ID valido} " + d + "ifid_reg.valid"), ("22", bus("ID PC", d + "ifid_reg.pc", 31)),
                                        ("22", bus("rs", d + "ifid_reg.instr", 25, 21)), ("22", bus("rt", d + "ifid_reg.instr", 20, 16)),
                                        ("28", "+{usa rs} " + d + "id_uses_rs"), ("28", "+{usa rt} " + d + "id_uses_rt")]),
                   ("EX distancia 1", [("28", "+{EX valido} " + d + "idex_reg.valid"), ("28", "+{EX wb_enable} " + d + "idex_reg.wb_enable"),
                                        ("22", bus("EX wb_addr", d + "idex_reg.wb_addr", 4))]),
                   ("MEM distancia 2", [("28", "+{MEM valido} " + d + "exmem_reg.valid"), ("28", "+{MEM wb_enable} " + d + "exmem_reg.wb_enable"),
                                         ("22", bus("MEM wb_addr", d + "exmem_reg.wb_addr", 4))]),
                   ("Deteccao", [("28", "+{data_conflict} " + d + "data_conflict")])]
    elif tipo == "estrutural":
        grupos += [("MEM", [("28", "+{MEM valido} " + d + "exmem_reg.valid"), ("28", "+{MEM is_lw} " + d + "exmem_reg.is_lw"),
                             ("28", "+{MEM is_sw} " + d + "exmem_reg.is_sw")]),
                   ("Deteccao", [("28", "+{structural_conflict} " + d + "structural_conflict")])]
    else:
        grupos += [("ID", [("28", "+{ID valido} " + d + "ifid_reg.valid"), ("22", bus("ID PC", d + "ifid_reg.pc", 31))]),
                   ("EX", [("28", "+{EX valido} " + d + "idex_reg.valid"), ("28", "+{EX is_beq} " + d + "idex_reg.is_beq"),
                            ("22", bus("EX pc_plus4", d + "idex_reg.pc_plus4", 31)), ("28", "+{zero ULA} " + d + "alu_zero"),
                            ("28", "+{branch_taken} " + d + "branch_taken")]),
                   ("Deteccao", [("28", "+{control_conflict} " + d + "control_conflict")])]
    grupos.append(("Saidas R3", [("28", "+{hazard_abort} top.tb_cpu.hazard_abort"), ("28", "+{frozen} " + d + "frozen"),
                                  ("22", bus("hazard_type", "top.tb_cpu.hazard_type", 1)), ("22", bus("hazard_pc", "top.tb_cpu.hazard_pc", 31)),
                                  ("24", bus("hazard_cycle", "top.tb_cpu.hazard_cycle", 31)), ("22", bus("stage_valid", "top.tb_cpu.stage_valid", 4))]))
    letras = "ABCDEFGH"
    ms = [(c, tx) for c, tx in marks]
    tempos = [t[c] for c, _ in ms]
    tempos = tempos[:1] + tempos          # o 1º valor é o cursor principal; depois vêm A, B, C...
    L = [f"[*] MicroProj-AOC: detecção e aborto ({tipo}) na O2, gerado por scripts/waveform_aborto.py",
         f'[dumpfile] "{os.path.basename(dump)}"', "[timestart] 0", "[size] 1800 900", "[pos] -1 -1",
         "*-24.000000 " + " ".join(str(x) for x in tempos) + " " + " ".join("-1" for _ in range(27 - len(tempos)))]
    for i, (c, tx) in enumerate(ms):
        L.append(f"[markername] {letras[i]}C{c} {curto(tx)}")
    L += ["[signals_width] 300", "[sst_expanded] 1", "@200",
          f"-Ciclo k = ({(linhas[0]['t'] - per // 2) // 1_000_000} ns + (k-1) x {per // 1_000_000} ns) a "
          f"({(linhas[0]['t'] - per // 2) // 1_000_000} ns + k x {per // 1_000_000} ns); amostragem na borda de descida"]
    for nome, itens in grupos:
        L += ["@800200", f"-{nome}"]
        for flag, sp in itens:
            L += [f"@{flag}", sp]
        L += ["@1000200", f"-{nome}"]
    L += ["[pattern_trace] 1", "[pattern_trace] 0"]
    return "\n".join(L) + "\n"


# --------------------------------------------------------------------------- main
def main():
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    ghw, asm_path, saida, nome, tipo = sys.argv[1:]
    if tipo not in TIPO_COD:
        sys.exit("tipo: dados | estrutural | controle")
    asm = load_asm(asm_path)
    linhas, A = coletar(Signals(ghw), asm)
    conferir(linhas, A, TIPO_COD[tipo], tipo)
    rows = spec(tipo, asm)
    marks = marcadores(tipo, linhas, A, asm)
    os.makedirs(saida, exist_ok=True)
    titulo = (f"O2 — {nome.upper()}: conflito de {tipo} (hazard_type = {TIPO_COD[tipo]}); "
              f"aborto no ciclo {A}, hazard_pc = {hx(linhas[A - 1]['hpc'], 8)}")
    open(f"{saida}/{nome}_aborto.svg", "w", encoding="utf-8").write(desenhar(titulo, linhas, A, rows, marks, tipo))
    with open(f"{saida}/{nome}_aborto.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter=";")
        cols = ["ciclo", "if_pc", "id_pc", "ex_pc", "mem_pc", "c_dados", "c_estr", "c_ctrl", "abort", "frozen", "tipo", "hpc", "hciclo", "sv", "ret"]
        w.writerow(cols)
        for r in linhas:
            w.writerow([hx(r[c]) if c in ("if_pc", "id_pc", "ex_pc", "mem_pc", "hpc", "sv") else r[c] for c in cols])
    open(f"{saida}/{nome}_aborto.gtkw", "w", encoding="utf-8").write(gtkw(linhas, A, tipo, ghw, marks))
    print(f"{nome}: aborto no ciclo {A} (tipo {TIPO_COD[tipo]}, hazard_pc {hx(linhas[A - 1]['hpc'], 8)}); "
          f"estável por 4 ciclos; detecção conferida nos {A} ciclos")


if __name__ == "__main__":
    main()
