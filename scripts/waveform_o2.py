#!/usr/bin/env python3
"""Waveform anotada da O2 a partir do dump GHW do GHDL (issue #17).

Uso:
    python3 scripts/waveform_o2.py build/t0_o2.ghw tracos/t0.asm docs/waveforms t0_o2

Lê o .ghw com o ghwdump (vem com o GHDL), amostra cada ciclo na borda de descida
— a mesma convenção do tb_cpu: ciclo 1 = primeiro ciclo após a liberação do
reset — e gera, sem nenhum valor fixo no código:
    <nome>_completo.svg      todos os ciclos, sinais agrupados por estágio
    <nome>_enchimento.svg    zoom no início (instrução em cada estágio)
    <nome>_esvaziamento.svg  zoom no fim
    <nome>_ciclos.csv        PC e validade de cada estágio, ciclo a ciclo
    <nome>.gtkw              sessão do GTKWave: grupos por estágio, hex e marcadores

Os registradores entre estágios são records; o GHW os guarda campo a campo e o
script separa os campos pelo layout informado pelo próprio ghwdump (-t).
EX/MEM e MEM/WB não guardam o PC no RTL: o PC de MEM/WB é o PC que estava em
EX um/dois ciclos antes (exato na O2, que não tem stall nem flush).

Variável de ambiente GHWDUMP: comando do ghwdump (padrão: "ghwdump" no PATH ou,
se não houver, dentro da distrobox "vhdl").
"""
import csv
import os
import re
import shlex
import shutil
import subprocess
import sys
from html import escape

DUT = "/tb_cpu/gen_o2/dut/"


# --------------------------------------------------------------------------- ghwdump
def ghwdump_cmd():
    if os.environ.get("GHWDUMP"):
        return shlex.split(os.environ["GHWDUMP"])
    if shutil.which("ghwdump"):
        return ["ghwdump"]
    if shutil.which("distrobox-enter"):
        return ["distrobox-enter", "-n", "vhdl", "--", "ghwdump"]
    sys.exit("ghwdump não encontrado (defina GHWDUMP)")


def run(args, ghw):
    # Até 3 tentativas: via distrobox, o podman às vezes falha ao registrar o fim da
    # sessão (exit != 0 com a saída já impressa) — falha do contêiner, não do ghwdump.
    for tentativa in range(3):
        out = subprocess.run(ghwdump_cmd() + args + [ghw], capture_output=True, text=True,
                             stdin=subprocess.DEVNULL)
        if out.returncode == 0:
            return out.stdout
    sys.exit(out.stderr)


def parse_types(text):
    """Larguras de subtipos e layout dos records: {nome: [(campo, largura)]}."""
    widths = {"std_logic": 1, "std_ulogic": 1, "boolean": 1, "bit": 1}
    records, cur = {}, None
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"type (\w+) is \(", line)
        if m:
            widths[m.group(1)] = 1          # enumeração: um único sinal
            continue
        m = re.match(r"subtype (\w+) is .*\((\d+) (?:downto|to) (\d+)\)", line)
        if m:
            widths[m.group(1)] = abs(int(m.group(2)) - int(m.group(3))) + 1
            continue
        m = re.match(r"type (\w+) is record", line)
        if m:
            cur = records.setdefault(m.group(1), [])
            continue
        if line.startswith("end record"):
            cur = None
            continue
        if cur is not None:
            m = re.match(r"(\w+): (\w+)", line)
            cur.append((m.group(1), m.group(2)))
    return {r: [(f, widths[t]) for f, t in fl] for r, fl in records.items()}


def parse_hierarchy(text):
    """{caminho: (tipo, primeiro_índice, último_índice)}"""
    sigs = {}
    for line in text.splitlines():
        m = re.match(r"\s*(?:signal|port-in|port-out) (\S+): (.+): #(\d+)(?:-#(\d+))?$", line)
        if m:
            path, typ, a, b = m.groups()
            sigs.setdefault(path, (typ.split()[0], int(a), int(b or a)))
    return sigs


def parse_snapshots(text):
    """Lista de (tempo_fs, {índice: valor}) — uma fotografia completa por mudança."""
    snaps, cur, t = [], None, None
    for line in text.splitlines():
        if line.startswith("Time is "):
            if cur is not None:
                snaps.append((t, cur))
            t, cur = int(line.split()[2]), {}
        else:
            m = re.match(r"#(\d+): '(.)'", line)
            if m:
                cur[int(m.group(1))] = m.group(2)
            else:
                m = re.match(r"#(\d+): (\w+)", line)   # enumerações
                if m:
                    cur[int(m.group(1))] = m.group(2)
    if cur is not None:
        snaps.append((t, cur))
    return snaps


# --------------------------------------------------------------------------- amostragem
class Signals:
    def __init__(self, ghw):
        self.records = parse_types(run(["-t"], ghw))
        self.hier = parse_hierarchy(run(["-H"], ghw))
        self.snaps = parse_snapshots(run(["-s"], ghw))

    def rng(self, path, field=None):
        typ, a, b = self.hier[path]
        if field is None:
            return a, b
        off = a
        for name, w in self.records[typ]:
            if name == field:
                return off, off + w - 1
            off += w
        raise KeyError(field)

    def bits(self, snap, path, field=None):
        a, b = self.rng(path, field)
        return "".join(snap.get(i, "U") for i in range(a, b + 1))

    def num(self, snap, path, field=None):
        s = self.bits(snap, path, field)
        return int(s, 2) if set(s) <= {"0", "1"} else None


def sample_cycles(sig):
    """Fotografia de cada ciclo, logo antes da borda de descida (convenção do tb_cpu)."""
    clk = sig.rng("/tb_cpu/clk")[0]
    rst = sig.rng("/tb_cpu/rst")[0]
    t_release = next(t for t, s in sig.snaps if s.get(rst) == "0")
    falls, prev = [], None
    for t, s in sig.snaps:
        v = s.get(clk)
        if prev == "1" and v == "0" and t > t_release:
            falls.append(t)
        prev = v
    out = []
    sample_cycles.times = falls
    for tf in falls:
        last = None
        for t, s in sig.snaps:
            if t >= tf:
                break
            last = s
        out.append(last)
    return out


def load_asm(path):
    """PC -> texto da instrução, montado em ordem a partir do .asm (texto em 0x0)."""
    text, pc = {}, 0
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("."):
            continue
        if ":" in line:
            line = line.split(":", 1)[1].strip()
            if not line:
                continue
        text[pc] = re.sub(r"\s+", " ", line.replace(" ,", ","))
        pc += 4
    return text


def build_table(sig):
    rows = []
    for k, s in enumerate(sample_cycles(sig), start=1):
        sv = sig.bits(s, "/tb_cpu/stage_valid")
        ex_p4 = sig.num(s, DUT + "idex_reg", "pc_plus4")
        r = {
            "ciclo": k,
            "t": sample_cycles.times[k - 1],
            "stage_valid": int(sv, 2),
            "if_v": int(sv[-1]), "if_pc": sig.num(s, DUT + "pc"),
            "if_instr": sig.num(s, DUT + "if_instr"),
            "id_v": int(sig.bits(s, DUT + "ifid_reg", "valid")),
            "id_pc": sig.num(s, DUT + "ifid_reg", "pc"),
            "id_instr": sig.num(s, DUT + "ifid_reg", "instr"),
            "ex_v": int(sig.bits(s, DUT + "idex_reg", "valid")),
            "ex_pc": (ex_p4 - 4) & 0xFFFFFFFF if ex_p4 is not None else None,
            "mem_v": int(sig.bits(s, DUT + "exmem_reg", "valid")),
            "wb_v": int(sig.bits(s, DUT + "memwb_reg", "valid")),
            "retired": sig.num(s, "/tb_cpu/retired"),
            "done": int(sig.bits(s, "/tb_cpu/done")),
            "abort": int(sig.bits(s, "/tb_cpu/hazard_abort")),
        }
        rows.append(r)
        if r["done"] or r["abort"]:
            break
    # PC de MEM e WB: o PC de EX um e dois ciclos antes (sem stall/flush na O2).
    for i, r in enumerate(rows):
        r["mem_pc"] = rows[i - 1]["ex_pc"] if i >= 1 else None
        r["wb_pc"] = rows[i - 2]["ex_pc"] if i >= 2 else None
    return rows


def phases(rows):
    """Ciclos de enchimento/esvaziamento, calculados a partir dos bits de validade."""
    full = [r["ciclo"] for r in rows if r["stage_valid"] & 0x1F == 0x1F]
    fetch = [r["ciclo"] for r in rows if r["if_v"]]
    first_wb = next(r["ciclo"] for r in rows if r["wb_v"])
    end = rows[-1]["ciclo"]
    return {
        "first_fetch": fetch[0],
        "first_full": full[0] if full else None,
        "last_full": full[-1] if full else None,
        "first_wb": first_wb,
        "last_fetch": fetch[-1],
        "drain_start": fetch[-1] + 1,
        "end": end,
    }


# --------------------------------------------------------------------------- SVG
STAGES = [("IF", "if"), ("ID", "id"), ("EX", "ex"), ("MEM", "mem"), ("WB", "wb")]
COL = {"enchimento": "#dbeafe", "cheio": "#dcfce7", "esvaziamento": "#ffedd5",
       "bus": "#1e3a8a", "bubble": "#9ca3af", "wave": "#111827", "mark": "#b91c1c"}


def hx(v, digits=2):
    return "—" if v is None else f"0x{v:0{digits}X}"


def svg_wave(rows, asm, ph, c0, c1, colw, title, out, detail):
    rows = [r for r in rows if c0 <= r["ciclo"] <= c1]
    lab_w, row_h, top = 210, 26, 130
    sigs = [("Relógio", [("clk", "clk", None)])]
    for st, k in STAGES:
        g = [(f"{st} válido", "bit", f"{k}_v"), (f"{st} PC" + (" *" if k in ("mem", "wb") else ""), "bus", k)]
        if detail and k == "id":
            g.append(("ID instrução", "instr", "id_instr"))
        sigs.append((f"Estágio {st}", g))
    sigs.append(("Saídas R3", [("stage_valid[4:0]", "sv", None),
                               ("retired", "num", "retired"), ("done", "bit", "done")]))
    n_rows = sum(len(g) for _, g in sigs) + len(sigs)
    width = lab_w + colw * len(rows) + 20
    height = top + n_rows * row_h + 18 + 5 * 15 + 30
    x = lambda c: lab_w + (c - c0) * colw
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
         f'font-family="DejaVu Sans Mono, monospace" font-size="11">',
         f'<rect width="100%" height="100%" fill="white"/>',
         f'<text x="10" y="20" font-size="15" font-weight="bold">{escape(title)}</text>']
    # faixas de fase
    def band(a, b, color, label):
        a, b = max(a, c0), min(b, c1)
        if a > b:
            return
        o.append(f'<rect x="{x(a)}" y="{top - 22}" width="{(b - a + 1) * colw}" '
                 f'height="{n_rows * row_h + 22}" fill="{color}"/>')
        o.append(f'<text x="{x(a) + (b - a + 1) * colw / 2}" y="{top - 8}" text-anchor="middle" '
                 f'font-size="11" font-weight="bold">{label}</text>')
    band(ph["first_fetch"], ph["first_full"] - 1, COL["enchimento"], "enchimento")
    band(ph["first_full"], ph["last_full"], COL["cheio"], "pipeline cheio")
    band(ph["drain_start"], ph["end"], COL["esvaziamento"], "esvaziamento")
    # cabeçalho de ciclos
    for r in rows:
        c = r["ciclo"]
        o.append(f'<text x="{x(c) + colw / 2}" y="{top - 28}" text-anchor="middle">C{c}</text>')
        o.append(f'<line x1="{x(c)}" y1="{top - 22}" x2="{x(c)}" y2="{top + n_rows * row_h}" '
                 f'stroke="#e5e7eb"/>')
    y = top
    for gname, g in sigs:
        o.append(f'<text x="8" y="{y + 17}" font-weight="bold" fill="#374151">{escape(gname)}</text>')
        o.append(f'<line x1="0" y1="{y + 1}" x2="{width}" y2="{y + 1}" stroke="#9ca3af"/>')
        y += row_h
        for label, kind, key in g:
            o.append(f'<text x="18" y="{y + 17}">{escape(label)}</text>')
            hi, lo = y + 5, y + row_h - 5
            for r in rows:
                c, xa = r["ciclo"], x(r["ciclo"])
                xb, xm = xa + colw, xa + colw / 2
                if kind == "clk":
                    o.append(f'<polyline fill="none" stroke="{COL["wave"]}" points="{xa},{lo} {xa},{hi} '
                             f'{xm},{hi} {xm},{lo} {xb},{lo}"/>')
                elif kind == "bit":
                    v = r[key]
                    yy = hi if v else lo
                    o.append(f'<line x1="{xa}" y1="{yy}" x2="{xb}" y2="{yy}" stroke="{COL["wave"]}" stroke-width="2"/>')
                    prev = next((p for p in rows if p["ciclo"] == c - 1), None)
                    if prev is not None and prev[key] != v:
                        o.append(f'<line x1="{xa}" y1="{hi}" x2="{xa}" y2="{lo}" stroke="{COL["wave"]}" stroke-width="2"/>')
                else:
                    if kind == "bus":
                        valid = r[f"{key}_v"]
                        v = r[f"{key}_pc"]
                        txt = hx(v) if valid else ("bolha" if colw >= 44 else "—")
                        sub = asm.get(v, "") if (valid and detail) else ""
                    elif kind == "instr":
                        valid = r["id_v"]
                        txt = f"{r[key]:08X}" if valid and r[key] is not None else "—"
                        sub = ""
                    elif kind == "sv":
                        valid, txt, sub = True, hx(r["stage_valid"] & 0x1F), ""
                    else:
                        valid, txt, sub = True, str(r[key]), ""
                    color = COL["bus"] if valid else COL["bubble"]
                    d = 4
                    o.append(f'<polygon fill="{"#eef2ff" if valid else "#f3f4f6"}" stroke="{color}" '
                             f'points="{xa + d},{hi} {xb - d},{hi} {xb},{y + row_h / 2} {xb - d},{lo} '
                             f'{xa + d},{lo} {xa},{y + row_h / 2}"/>')
                    fs = 11 if colw >= 44 else 9
                    o.append(f'<text x="{xm}" y="{y + row_h / 2 + 4}" text-anchor="middle" font-size="{fs}" '
                             f'fill="{color}">{escape(txt)}</text>')
                    if sub:
                        o.append(f'<title>{escape(sub)}</title>')
            y += row_h
            if detail and kind == "bus":
                # linha extra com o assembly da instrução em cada estágio
                pass
    # marcadores
    marks = [
        (ph["first_fetch"], f'C{ph["first_fetch"]}: IF busca {hx(rows[0]["if_pc"])} '
                            f'({asm.get(rows[0]["if_pc"], "")}) — início do enchimento'),
        (ph["first_full"], f'C{ph["first_full"]}: 1ª instrução em WB, 5 estágios válidos '
                           f'(stage_valid=0x1F), retired=1 — pipeline cheio'),
        (ph["last_fetch"], f'C{ph["last_fetch"]}: última busca, {hx(last_if_pc(rows, ph))} '
                           f'({asm.get(last_if_pc(rows, ph), "")}) em IF'),
        (ph["drain_start"], f'C{ph["drain_start"]}: IF vazio (stage_valid[0]=0) — início do esvaziamento'),
        (ph["end"], f'C{ph["end"]}: break em WB — done=1 (o break não conta em retired), fim'),
    ]
    yb = top + n_rows * row_h + 18
    vis = [(c, t) for c, t in marks if c0 <= c <= c1]
    for i, (c, t) in enumerate(vis):
        # na borda de início do ciclo, para não cortar os valores das células
        xc = x(c)
        o.append(f'<line x1="{xc}" y1="{top - 50}" x2="{xc}" y2="{top + n_rows * row_h}" '
                 f'stroke="{COL["mark"]}" stroke-dasharray="4 3" stroke-width="1.5"/>')
        o.append(f'<circle cx="{xc}" cy="{top - 58}" r="8" fill="{COL["mark"]}"/>')
        o.append(f'<text x="{xc}" y="{top - 54}" text-anchor="middle" fill="white" font-size="10" '
                 f'font-weight="bold">{i + 1}</text>')
    for i, (c, t) in enumerate(vis):
        o.append(f'<text x="10" y="{yb + i * 15}" fill="{COL["mark"]}">({i + 1}) {escape(t)}</text>')
    o.append(f'<text x="10" y="{height - 8}" fill="#4b5563" font-size="10">'
             f'Valores em hexadecimal; — = bolha (estágio sem instrução válida). * PC de MEM/WB = PC de EX 1/2 ciclos antes (EX/MEM e MEM/WB não '
             f'guardam PC; exato sem stall/flush). Ciclo 1 = 1º ciclo após o reset (convenção do tb_cpu).</text>')
    o.append("</svg>")
    # altura real com a legenda
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(o))


def last_if_pc(rows, ph):
    return next(r["if_pc"] for r in rows if r["ciclo"] == ph["last_fetch"])


def svg_detail(rows, asm, ph, c0, c1, title, out):
    """Zoom: cada célula mostra PC e assembly da instrução no estágio."""
    rows = [r for r in rows if c0 <= r["ciclo"] <= c1]
    longest = max((len(asm.get(r[f"{k}_pc"], "")) for r in rows for _, k in STAGES if r[f"{k}_v"]),
                  default=10)
    lab_w, row_h, top = 120, 40, 70
    colw = max(132, int(longest * 6.2) + 20)
    groups = STAGES + [("stage_valid", None), ("retired", None), ("done", None)]
    width = lab_w + colw * len(rows) + 20
    height = top + len(groups) * row_h + 30
    x = lambda c: lab_w + (c - c0) * colw
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
         f'font-family="DejaVu Sans Mono, monospace" font-size="11">',
         '<rect width="100%" height="100%" fill="white"/>',
         f'<text x="10" y="20" font-size="15" font-weight="bold">{escape(title)}</text>']
    for r in rows:
        c = r["ciclo"]
        if c < ph["first_full"]:
            col, lab = COL["enchimento"], "enchimento"
        elif c <= ph["last_full"]:
            col, lab = COL["cheio"], "cheio"
        else:
            col, lab = COL["esvaziamento"], "esvaziamento"
        o.append(f'<rect x="{x(c)}" y="{top - 30}" width="{colw}" height="{len(groups) * row_h + 30}" '
                 f'fill="{col}" stroke="white"/>')
        o.append(f'<text x="{x(c) + colw / 2}" y="{top - 16}" text-anchor="middle" font-weight="bold">'
                 f'C{c}</text>')
        o.append(f'<text x="{x(c) + colw / 2}" y="{top - 4}" text-anchor="middle" font-size="9" '
                 f'fill="#4b5563">{lab}</text>')
    y = top
    for name, key in groups:
        o.append(f'<text x="8" y="{y + row_h / 2 + 4}" font-weight="bold">{name}</text>')
        o.append(f'<line x1="0" y1="{y}" x2="{width}" y2="{y}" stroke="#9ca3af"/>')
        for r in rows:
            xa, xm = x(r["ciclo"]), x(r["ciclo"]) + colw / 2
            if key is not None:
                if r[f"{key}_v"]:
                    pc = r[f"{key}_pc"]
                    o.append(f'<rect x="{xa + 3}" y="{y + 3}" width="{colw - 6}" height="{row_h - 6}" rx="4" '
                             f'fill="white" stroke="{COL["bus"]}"/>')
                    o.append(f'<text x="{xm}" y="{y + 17}" text-anchor="middle" fill="{COL["bus"]}" '
                             f'font-weight="bold">{hx(pc)}</text>')
                    o.append(f'<text x="{xm}" y="{y + 31}" text-anchor="middle" font-size="10">'
                             f'{escape(asm.get(pc, ""))}</text>')
                else:
                    o.append(f'<text x="{xm}" y="{y + row_h / 2 + 4}" text-anchor="middle" '
                             f'fill="{COL["bubble"]}">bolha</text>')
            else:
                v = {"stage_valid": hx(r["stage_valid"] & 0x1F), "retired": str(r["retired"]),
                     "done": str(r["done"])}[name]
                o.append(f'<text x="{xm}" y="{y + row_h / 2 + 4}" text-anchor="middle">{v}</text>')
        y += row_h
    o.append(f'<text x="10" y="{height - 10}" fill="#4b5563" font-size="10">'
             f'Cada célula: PC (hex) e instrução no estágio. PC de MEM/WB = PC de EX 1/2 ciclos antes.</text>')
    o.append("</svg>")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(o))


# --------------------------------------------------------------------------- GTKWave
def bus(name, path, msb, lsb=0):
    bits = " ".join(f"{path}[{i}]" for i in range(msb, lsb - 1, -1))
    return f"#{{{name}}} {bits}"


def write_gtkw(rows, asm, ph, ghw, out):
    """Sessão do GTKWave para o mesmo .ghw (abrir: gtkwave build/<nome>.ghw <nome>.gtkw)."""
    d = "top.tb_cpu.gen_o2.dut."
    t = {r["ciclo"]: r["t"] for r in rows}
    marks = [  # mesmos ciclos da figura, no instante de amostragem do tb_cpu
        ("A", ph["first_fetch"], f'C{ph["first_fetch"]} IF busca 0x00: inicio do enchimento'),
        ("B", ph["first_full"], f'C{ph["first_full"]} 1a instr em WB, stage_valid=0x1F: pipeline cheio'),
        ("C", ph["last_fetch"], f'C{ph["last_fetch"]} ultima busca ({asm.get(last_if_pc(rows, ph), "")}) em IF'),
        ("D", ph["drain_start"], f'C{ph["drain_start"]} IF vazio: inicio do esvaziamento'),
        ("E", ph["end"], f'C{ph["end"]} break em WB: done=1'),
    ]
    named = {m: t[c] for m, c, _ in marks}
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    period = rows[1]["t"] - rows[0]["t"] if len(rows) > 1 else 10_000_000
    t0 = rows[0]["t"] - period // 2  # início do ciclo 1 (meio período antes da descida)
    L = ["[*] MicroProj-AOC: T0 na O2, gerado por scripts/waveform_o2.py (issue #17)",
         f'[dumpfile] "{os.path.basename(ghw)}"',
         "[timestart] 0", "[size] 1800 950", "[pos] -1 -1",
         "*-24.000000 %d %s" % (named["A"], " ".join(str(named.get(c, -1)) for c in letters))]
    L += [f"[markername] {m}{txt}" for m, _, txt in marks]
    L += ["[signals_width] 330", "[sst_expanded] 1"]

    def group(name, items):
        L.append("@800200")
        L.append(f"-{name}")
        for flag, spec in items:
            L.append(f"@{flag}")
            L.append(spec)
        L.append("@1000200")
        L.append(f"-{name}")

    L += ["@200", f"-Ciclo k = ({t0 // 1_000_000} ns + (k-1) x {period // 1_000_000} ns) a "
                  f"({t0 // 1_000_000} ns + k x {period // 1_000_000} ns); amostragem na borda de descida"]
    group("Relogio", [("28", "+{clk} top.tb_cpu.clk"), ("28", "+{rst} top.tb_cpu.rst")])
    group("Estagio IF", [("28", "+{IF valido (stage_valid[0])} top.tb_cpu.stage_valid[0]"),
                         ("22", bus("IF PC", d + "pc", 31)),
                         ("22", bus("IF instrucao", d + "if_instr", 31))])
    group("Estagio ID  (IF/ID)", [("28", "+{ID valido} " + d + "ifid_reg.valid"),
                                  ("22", bus("ID PC", d + "ifid_reg.pc", 31)),
                                  ("22", bus("ID instrucao", d + "ifid_reg.instr", 31))])
    group("Estagio EX  (ID/EX)", [("28", "+{EX valido} " + d + "idex_reg.valid"),
                                  ("22", bus("EX PC+4", d + "idex_reg.pc_plus4", 31))])
    group("Estagio MEM (EX/MEM)", [("28", "+{MEM valido} " + d + "exmem_reg.valid"),
                                   ("22", bus("MEM alu_result", d + "exmem_reg.alu_result", 31))])
    group("Estagio WB  (MEM/WB)", [("28", "+{WB valido} " + d + "memwb_reg.valid"),
                                   ("22", bus("WB registrador", d + "memwb_reg.wb_addr", 4)),
                                   ("22", bus("WB dado", d + "memwb_reg.wb_data", 31))])
    group("Saidas R3", [("22", bus("stage_valid", "top.tb_cpu.stage_valid", 9)),
                        ("24", bus("retired", "top.tb_cpu.retired", 1)),
                        ("28", "+{done} top.tb_cpu.done")])
    L.append("[pattern_trace] 1")
    L.append("[pattern_trace] 0")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


# --------------------------------------------------------------------------- main
def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    ghw, asm_path, outdir, name = sys.argv[1:]
    os.makedirs(outdir, exist_ok=True)
    asm = load_asm(asm_path)
    rows = build_table(Signals(ghw))
    ph = phases(rows)
    prog = os.path.basename(asm_path)

    with open(os.path.join(outdir, f"{name}_ciclos.csv"), "w", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["ciclo", "stage_valid", "IF_pc", "ID_pc", "EX_pc", "MEM_pc", "WB_pc",
                    "retired", "done", "instr_IF", "instr_WB"])
        for r in rows:
            cell = lambda k: hx(r[f"{k}_pc"]) if r[f"{k}_v"] else "bolha"
            w.writerow([r["ciclo"], hx(r["stage_valid"] & 0x1F)] + [cell(k) for _, k in STAGES] +
                       [r["retired"], r["done"],
                        asm.get(r["if_pc"], "") if r["if_v"] else "",
                        asm.get(r["wb_pc"], "") if r["wb_v"] else ""])

    end = ph["end"]
    svg_wave(rows, asm, ph, 1, end, 34, f"O2 executando {prog}: C1–C{end} (sinais por estágio)",
             os.path.join(outdir, f"{name}_completo.svg"), detail=False)
    a = ph["first_fetch"]
    svg_detail(rows, asm, ph, a, min(ph["first_full"] + 2, end),
               f"O2 — enchimento do pipeline ({prog})", os.path.join(outdir, f"{name}_enchimento.svg"))
    svg_detail(rows, asm, ph, max(ph["last_fetch"] - 2, 1), end,
               f"O2 — esvaziamento do pipeline ({prog})", os.path.join(outdir, f"{name}_esvaziamento.svg"))

    write_gtkw(rows, asm, ph, ghw, os.path.join(outdir, f"{name}.gtkw"))

    print(f"{len(rows)} ciclos; enchimento C{ph['first_fetch']}–C{ph['first_full'] - 1}, "
          f"cheio C{ph['first_full']}–C{ph['last_full']}, esvaziamento C{ph['drain_start']}–C{end}; "
          f"instruções concluídas: {sum(r['retired'] for r in rows)}")


if __name__ == "__main__":
    main()
