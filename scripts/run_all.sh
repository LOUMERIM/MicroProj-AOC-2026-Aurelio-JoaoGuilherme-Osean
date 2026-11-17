#!/usr/bin/env bash
# run_all (R7, issue #20): compila, testa, simula todos os traços e gera as métricas
# e as tabelas com um único comando:
#
#     ./scripts/run_all.sh
#
# Passos (para no primeiro erro, com código de saída != 0):
#   1. confere as ferramentas (ghdl, make, python3)
#   2. make clean + make test-unit          testes isolados dos componentes
#   3. make metricas                        traços limpos (T0 e série S) na O1 e na O2
#                                           -> metricas.csv (registradores conferidos)
#   4. traços de conflito TD, TE e TC       abortam na O2 com o tipo, hazard_pc e
#                                           hazard_cycle esperados; rodam limpos na O1
#                                           -> resultados/conflitos.csv
#   5. scripts/tabelas_metricas.py          -> resultados/tabelas.md
#
# Não depende de caminho absoluto nem do MARS: os .hex e _esperado.txt estão versionados.
#
# Período de clock (R6, issue #21): por padrão 0,22 ns nas duas organizações, pela tabela
# de atrasos de docs/periodo-clock.md. Outro critério: PERIODO_O1_NS=... PERIODO_O2_NS=...
set -uo pipefail
export PERIODO_O1_NS="${PERIODO_O1_NS:-0.22}"
export PERIODO_O2_NS="${PERIODO_O2_NS:-0.22}"

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"
RES=resultados
LOG=build/run_all.log

falha() { echo; echo "run_all: FALHOU — $*" >&2; [ -f "$LOG" ] && echo "(saída completa em $LOG)" >&2; exit 1; }
etapa() { echo; echo "==> $*"; }

# ------------------------------------------------------------------ 1. ferramentas
etapa "1/5 ferramentas"
for cmd in ghdl make python3; do
    command -v "$cmd" >/dev/null 2>&1 || falha "'$cmd' não encontrado no PATH"
done
ghdl --version | head -1
grep -q '^metricas:' Makefile || falha "o Makefile não tem o alvo 'metricas' (issue #18)"

# ------------------------------------------------------------------ 2. testes unitários
etapa "2/5 compilação e testes unitários"
make -s clean
mkdir -p build "$RES"
make test-unit >"$LOG" 2>&1 </dev/null || falha "make test-unit"
grep -o "tb_[a-z_]* passed" "$LOG" | sed 's/^/    /'

# ------------------------------------------------------------------ 3. métricas
etapa "3/5 traços limpos (T0 e série S) na O1 e na O2"
make metricas >"$LOG" 2>&1 </dev/null || { grep -E "ERRO|error|failure" "$LOG" | head -5; falha "make metricas"; }
grep -o "O[12]: fim da simulação.*" "$LOG" | paste -d' ' <(grep "^== " "$LOG" | sed 's/^== //') - | sed 's/^/    /'

# ------------------------------------------------------------------ 4. conflitos
etapa "4/5 traços de conflito na O2 (e limpos na O1)"
# traço;tipo esperado (1 dados, 2 estrutural, 3 controle);MEM_UNIFICADA;hazard_pc;hazard_cycle
# (array + </dev/null: o ghdl pode rodar via distrobox, que consome o stdin do laço)
CONFLITOS=("td;1;false;00000014;7" "te;2;true;00000018;7" "tc;3;false;00000018;9")
verificados=0
echo "traco;organizacao;tipo_esperado;tipo_detectado;hazard_pc_esperado;hazard_pc;hazard_cycle_esperado;hazard_cycle;resultado" >"$RES/conflitos.csv"
for spec in "${CONFLITOS[@]}"; do
    IFS=';' read -r t tipo memuni pc ciclo <<<"$spec"
    prog="tracos/$t.hex"; esp="tracos/${t}_esperado.txt"
    make sim ORG=O2 SLOTS=5 PROG="$prog" ESPERADO="$esp" ABORTO=true TIPO="$tipo" \
         MEMUNI="$memuni" PCESP="$pc" >"$LOG" 2>&1 </dev/null
    rc=$?
    linha=$(grep -o "O2: ABORTO.*" "$LOG" | head -1)
    det_tipo=$(sed -n 's/.*tipo=\([01]*\).*/\1/p' <<<"$linha")
    det_pc=$(sed -n 's/.*pc=0x\([0-9A-Fa-f]*\).*/\1/p' <<<"$linha")
    det_ciclo=$(sed -n 's/.*ciclo=\([0-9]*\).*/\1/p' <<<"$linha")
    case "$tipo" in 1) esperado_tipo=01 ;; 2) esperado_tipo=10 ;; 3) esperado_tipo=11 ;; esac
    ok=ok
    if [ $rc -ne 0 ] || grep -qE "\(report error\)|\(assertion error\)|failure" "$LOG" \
       || [ "$det_tipo" != "$esperado_tipo" ] || [ "${det_pc^^}" != "$pc" ] || [ "$det_ciclo" != "$ciclo" ]; then
        ok=FALHOU
    fi
    echo "$t;O2;$esperado_tipo;${det_tipo:-};0x$pc;0x${det_pc:-};$ciclo;${det_ciclo:-};$ok" >>"$RES/conflitos.csv"
    printf '    %s O2: %s  [%s]\n' "${t^^}" "${linha:-sem aborto}" "$ok"
    [ "$ok" = ok ] || falha "${t^^} na O2 não abortou como esperado"

    # Na O1 (sem pipeline) o mesmo traço executa até o fim e confere o esperado.
    make sim ORG=O1 PROG="$prog" ESPERADO="$esp" >"$LOG" 2>&1 </dev/null
    rc=$?
    fim=$(grep -o "O1: fim da simulação.*" "$LOG" | head -1)
    if [ $rc -ne 0 ] || ! grep -q " 0 erro(s)" <<<"$fim"; then
        falha "${t^^} na O1 deveria executar sem erros"
    fi
    echo "$t;O1;00;00;-;-;-;-;ok" >>"$RES/conflitos.csv"
    printf '    %s O1: %s  [ok]\n' "${t^^}" "$fim"
    verificados=$((verificados + 1))
done
[ "$verificados" -eq "${#CONFLITOS[@]}" ] \
    || falha "só $verificados de ${#CONFLITOS[@]} traços de conflito foram verificados"

# ------------------------------------------------------------------ 5. tabelas
etapa "5/5 tabelas"
python3 scripts/tabelas_metricas.py metricas.csv "$RES/conflitos.csv" >"$RES/tabelas.md" \
    || falha "geração das tabelas"
echo "    metricas.csv, $RES/conflitos.csv e $RES/tabelas.md (períodos O1=${PERIODO_O1_NS} ns, O2=${PERIODO_O2_NS} ns)"

echo
echo "run_all: OK"
