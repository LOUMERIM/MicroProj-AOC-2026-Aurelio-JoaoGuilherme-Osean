#!/usr/bin/env python3
"""Gera a série S (R5): variações do T0 com 5, 10, 20, 50, 100 e 200 instruções úteis.

Uso:
    python3 scripts/gerar_serie_s.py [--mars CAMINHO/Mars4_5.jar] [--tamanhos 5,10,20,50,100,200]

Para cada tamanho n grava em tracos/:
    sNNN.asm            as n primeiras instruções úteis da repetição do corpo do T0 + break
    sNNN.hex            montado pelo MARS (texto a partir do endereço 0)
    sNNN_esperado.txt   registradores finais, executando o .asm no MARS

Por que S_n continua sem conflitos (mesmas regras do T0):
  * um prefixo de um programa sem conflitos não tem conflitos (cada dependência só
    olha para instruções anteriores);
  * ao emendar uma cópia do T0 na seguinte, o bloco A da nova cópia só lê $zero e
    cada registrador lido depois é reescrito dentro da própria cópia a distância >= 3;
    os beq comparam os mesmos valores do T0 (diferentes), então continuam não tomados.
  Os rótulos ganham o sufixo _cK (K = número da cópia) para não se repetirem.
O script também confere, no texto gerado, que nenhuma instrução lê um registrador
escrito a distância 1 ou 2 (escritas em $zero não contam).

MARS: --mars, variável MARS_JAR ou ~/Aplicativos/MARS/Mars4_5.jar.
"""
import argparse
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T0 = os.path.join(RAIZ, "tracos", "t0.asm")
REGS = [4] + list(range(8, 24))          # $a0, $t0-$t7, $s0-$s7 (os mesmos do t0_esperado)
NOMES = {"zero": 0, "at": 1, "v0": 2, "v1": 3, "a0": 4, "a1": 5, "a2": 6, "a3": 7,
         **{f"t{i}": 8 + i for i in range(8)}, **{f"s{i}": 16 + i for i in range(8)},
         "t8": 24, "t9": 25}


def corpo_t0():
    """Itens do T0 em ordem: ('rotulo', nome) ou ('instr', texto). Sem o break."""
    itens = []
    for bruta in open(T0, encoding="utf-8"):
        linha = bruta.split("#", 1)[0].strip()
        if not linha or linha.startswith("."):
            continue
        m = re.match(r"(\w+):\s*(.*)$", linha)
        if m:
            itens.append(("rotulo", m.group(1)))
            linha = m.group(2)
            if not linha:
                continue
        if linha == "break":
            break
        itens.append(("instr", re.sub(r"\s+", " ", linha)))
    return itens


def gerar_asm(n, itens):
    uteis = sum(1 for t, _ in itens if t == "instr")
    linhas, feitas, copia = [], 0, 0
    while feitas < n:
        copia += 1
        sufixo = lambda nome: f"{nome}_c{copia}"
        for tipo, valor in itens:
            if tipo == "rotulo":
                linhas.append(f"{sufixo(valor)}:")
                continue
            if feitas == n:
                break
            texto = valor
            m = re.match(r"(beq\s+\$\w+,\s*\$\w+,\s*)(\w+)$", texto)
            if m:
                texto = m.group(1) + sufixo(m.group(2))
            linhas.append(f"{texto:<32}# 0x{feitas * 4:03X}")
            feitas += 1
    # rótulos pendurados depois da última instrução apontam para o break (beq não tomado)
    cab = [".text",
           f"# S{n:03d} — série S (R5): {n} instruções úteis, sem conflitos.",
           f"# Gerado por scripts/gerar_serie_s.py a partir de tracos/t0.asm "
           f"({uteis} instruções úteis por cópia; {copia} cópia(s), a última truncada se preciso).",
           "# Não editar à mão: rode o script de novo."]
    return "\n".join(cab + linhas + [f"{'break':<32}# 0x{n * 4:03X} fim (não conta no CPI)"]) + "\n"


def regs_da_instr(texto):
    """(destino, [lidos]) da instrução, nos formatos do subconjunto da ISA."""
    op, *resto = texto.replace(",", " ").split()
    r = [NOMES[x[1:]] for x in re.findall(r"\$\w+", texto)]
    if op in ("add", "sub", "and", "or", "slt"):
        return r[0], [r[1], r[2]]
    if op == "addi":
        return r[0], [r[1]]
    if op == "lw":
        return r[0], [r[1]]
    if op == "sw":
        return None, [r[0], r[1]]
    if op == "beq":
        return None, [r[0], r[1]]
    raise ValueError(texto)


def conferir_sem_conflito(asm):
    instrs = [l.split("#", 1)[0].strip() for l in asm.splitlines()]
    instrs = [i for i in instrs if i and not i.startswith(".") and not i.endswith(":") and i != "break"]
    destinos = []
    for k, texto in enumerate(instrs):
        dest, lidos = regs_da_instr(texto)
        for dist in (1, 2):
            if k - dist >= 0:
                d = destinos[k - dist]
                if d not in (None, 0) and d in lidos:
                    sys.exit(f"conflito de dados: instr {k} ({texto}) lê ${d} escrito a distância {dist}")
        destinos.append(dest)


def mars(jar, *args):
    out = subprocess.run(["java", "-jar", jar, "nc"] + list(args), capture_output=True, text=True)
    return out.stdout + out.stderr


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mars", default=os.environ.get("MARS_JAR",
                                                     os.path.expanduser("~/Aplicativos/MARS/Mars4_5.jar")))
    ap.add_argument("--tamanhos", default="5,10,20,50,100,200")
    a = ap.parse_args()
    if not os.path.isfile(a.mars):
        sys.exit(f"MARS não encontrado em {a.mars} (use --mars ou MARS_JAR)")

    itens = corpo_t0()
    for n in (int(x) for x in a.tamanhos.split(",")):
        base = os.path.join(RAIZ, "tracos", f"s{n:03d}")
        asm = gerar_asm(n, itens)
        conferir_sem_conflito(asm)
        with open(base + ".asm", "w", encoding="utf-8") as f:
            f.write(asm)

        mars(a.mars, "a", "mc", "CompactTextAtZero", "dump", ".text", "HexText", base + ".hex", base + ".asm")
        palavras = sum(1 for l in open(base + ".hex") if l.strip())
        if palavras != n + 1:
            sys.exit(f"{base}.hex tem {palavras} palavras; esperado {n + 1}")

        saida = mars(a.mars, "mc", "CompactDataAtZero", *map(str, REGS), base + ".asm")
        valores = dict(re.findall(r"^\$(\d+)\s+0x([0-9a-fA-F]{8})", saida, re.M))
        if "break instruction executed" not in saida or len(valores) != len(REGS):
            sys.exit(f"execução no MARS de {base}.asm não terminou no break:\n{saida}")
        with open(base + "_esperado.txt", "w", encoding="utf-8") as f:
            f.write(f"# S{n:03d} — estado final esperado (gerado no MARS 4.5 com CompactDataAtZero\n"
                    f"# por scripts/gerar_serie_s.py a partir de tracos/s{n:03d}.asm).\n"
                    "# Formato: <numero_do_registrador> <valor_hex_32bits>\n")
            for r in REGS:
                f.write(f"{r} {valores[str(r)].upper()}\n")
        print(f"s{n:03d}: {n} instruções úteis + break -> .asm, .hex ({palavras} palavras), _esperado.txt")


if __name__ == "__main__":
    main()
