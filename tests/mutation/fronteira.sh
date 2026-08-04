#!/usr/bin/env bash
# Mutacao da FRONTEIRA EXTERNA. Alvo separado porque a garantia nao vive no gate nem no instalador:
# vive na configuracao que decide qual check-run o ruleset avalia.
#
# Existe porque `tests/unit/fronteira-externa.sh` nasceu VERDE. Uma suite que nunca reprovou nao
# demonstrou discriminar nada - e o defeito exato que este repositorio ja pagou duas vezes
# (docs/adr/0020, regra 2): o unico obstaculo do teste era um hash desalinhado, e ele passava com
# a checagem de posse removida. Aqui cada mutante remove UMA garantia e exige o caso certo morrer.
#
# DIFERENCA DE MECANICA em relacao aos outros runners de mutacao deste repo: eles mutam o arquivo
# NO LUGAR e restauram no trap. Aqui a suite aceita `FRONTEIRA_WF_DIR`, entao a mutacao acontece
# numa COPIA em diretorio temporario. O repositorio nunca fica, nem por um instante, num estado
# em que o workflow real esta quebrado - o que tambem elimina a corrida que tests/lib/lock.sh
# existe para conter.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
SUITE="tests/unit/fronteira-externa.sh"
SRC=".github/workflows"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0; EXPECTED_MUTANTS=4

python3 -c 'import yaml' 2>/dev/null || {
  echo "NAO VERIFICADO: pyyaml ausente - a mutacao da fronteira nao pode ser avaliada." >&2; exit 2; }

echo "== baseline =="
if FRONTEIRA_WF_DIR="$SRC" bash "$SUITE" >/dev/null 2>&1; then
  echo "  PASS  baseline verde"
else
  echo "  FAIL  baseline vermelho; abortando"; exit 1
fi

# $1=id  $2=descricao  $3=comando de mutacao (recebe $D)  $4=trecho esperado no FAIL
mutante(){
  local id="$1" desc="$2" mut="$3" esperado="$4"
  local D="$TMP/$id"; rm -rf "$D"; mkdir -p "$D"; cp "$SRC"/*.yml "$D/"
  ( D="$D"; eval "$mut" )
  # A MUTACAO FOI APLICADA? Sem esta checagem, um padrao que nao casa produz "mutante morto"
  # por arquivo intacto - falso verde com a forma de rigor.
  if diff -rq "$SRC" "$D" >/dev/null 2>&1; then
    echo "  FAIL  $id NAO FOI APLICADO (padrao nao casa) - $desc"; F=$((F+1)); return
  fi
  local out rc
  out="$(FRONTEIRA_WF_DIR="$D" bash "$SUITE" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $id SOBREVIVEU - $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*$esperado"; then
    echo "  PASS  $id morto pelo caso certo ($esperado)"; P=$((P+1))
  else
    echo "  FAIL  $id: reprovou, mas nao em '$esperado' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
}

echo "== mutacao da fronteira externa =="

# MF1: o job de push volta a usar o nome do contexto exigido. E o defeito ORIGINAL medido:
# dois check-runs homonimos sobre o mesmo SHA.
mutante MF1 "colisao de contexto entre push e PR" \
  'sed -i "s/^  verify-push:/  verify-pr:/; s/^    name: verify-push$/    name: verify-pr/" "$D/verify-push.yml"' \
  "sem nome de job duplicado"

# MF2: o workflow de push passa a disparar tambem em pull_request - dois jobs decisorios, e o
# required check por nome deixa de discriminar qual avaliar.
mutante MF2 "dois jobs respondem por pull_request" \
  'sed -i "s/^on:\$/on:\n  pull_request:/" "$D/verify-push.yml"' \
  "um unico job decisorio"

# MF3: os dois workflows divergem no QUE verificam. E o preco de ter dois arquivos; se este
# mutante sobrevive, a duplicacao virou drift silencioso e a escolha de desenho fica indefensavel.
mutante MF3 "o workflow de push deixa de rodar a mutacao do gate" \
  'python3 - "$D/verify-push.yml" <<PY
import sys
p=sys.argv[1]; L=open(p).read().split("\n")
i=[k for k,l in enumerate(L) if "tests/mutation/run.sh" in l][0]
del L[i-1:i+1]
open(p,"w").write("\n".join(L))
PY' \
  "passos do job decisorio e do de push sao identicos"

# MF4: o cabecalho volta a mandar exigir "verify" no ruleset enquanto o job produz "verify-pr".
# Drift doc/mecanismo: o operador configuraria um contexto que ninguem reporta, e o PR ficaria
# pendente para sempre. Fail-closed, mas por motivo errado e sem sinal.
mutante MF4 "cabecalho manda exigir um contexto que nao existe" \
  'sed -i "s/required status check = \"verify-pr\"/required status check = \"verify\"/" "$D/verify-pr.yml"' \
  "contexto declarado no cabecalho"

echo
printf 'mutantes_esperados=%s  mortos=%s  falhas=%s\n' "$EXPECTED_MUTANTS" "$P" "$F"
if [ "$F" -eq 0 ] && [ "$P" -eq "$EXPECTED_MUTANTS" ]; then
  echo "mutacao da fronteira verde"; exit 0
else
  echo "mutacao da fronteira VERMELHA"; exit 1
fi
