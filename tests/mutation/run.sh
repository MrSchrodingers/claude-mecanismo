#!/usr/bin/env bash
# VALIDACAO POR MUTACAO. Remove cada garantia do gate e EXIGE que a regressao reprove.
#
# Por que isto e obrigatorio (docs/adr/0020, regra de metodo 2): a suite anterior deste repo
# tinha 40 casos verdes e sobreviveu ao false-green do throttle - porque o helper `limpa()`
# apagava o carimbo antes de cada caso, contornando o mecanismo em vez de testa-lo.
# Um teste que sobrevive ao mutante nao testa a garantia: testa outra coisa.
#
# Contrato: para cada mutante, a suite de regressao DEVE sair != 0. Mutante sobrevivente
# (suite verde com a garantia removida) e FALHA DESTE ARQUIVO.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ORIG="evidence/hooks/verify-gate.sh"
REG="tests/unit/regressao-gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0

mutante(){ # $1=nome  $2=descricao da garantia removida  $3..=comandos sed
  local nome="$1" desc="$2"; shift 2
  cp -f "$TMP/orig.sh" "$ORIG"
  "$@"
  if ! bash -n "$ORIG" 2>/dev/null; then
    echo "  SKIP  $nome (mutante nao compila - sed nao casou)"; cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if bash "$REG" >/dev/null 2>&1; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  else
    echo "  PASS  $nome morto (suite reprovou ao remover: $desc)"; P=$((P+1))
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao do gate: cada garantia removida DEVE quebrar a regressao =="

# M1 - cache aceita qualquer veredito, nao so `pass` (era o false-green do throttle)
mutante M1 "so veredito 'pass' e reutilizavel" \
  sed -i 's/= "pass" \]; then/= "pass" ] || true; then/' "$ORIG"

# M2 - avisar por stderr+exit 0 em vez de additionalContext (canal inerte, ADR 0021)
mutante M2 "additionalContext como canal de aviso" \
  sed -i 's|^aviso(){ jq -cn|aviso(){ printf "%s\\n" "$1" >\&2; exit 0; }\nunused_aviso(){ jq -cn|' "$ORIG"

# M3 - identidade por NOME em vez de bytes (nao ve conteudo de untracked)
mutante M3 "identidade sobre bytes do arquivo" \
  sed -i 's|printf .%s %s\\n. "$f" "$(sha256sum "$ROOT/$f" 2>/dev/null \| cut -d. . -f1)"|printf "%s\\n" "$f"|' "$ORIG"

# M4 - para no primeiro adaptador aplicavel (ponto cego de monorepo)
mutante M4 "conjuncao sobre TODOS os adaptadores" \
  sed -i 's|APLICAVEIS+=("$a"); ECOS="$ECOS $(jq -r ..ecosystem // "?". "$a")"; break|APLICAVEIS=("$a"); break 2|' "$ORIG"

# M5 - tabela ausente sai 0 em silencio (inercia silenciosa)
mutante M5 "fail-closed quando a tabela some" \
  sed -i 's|^  reporta "GATE - tabela de adaptadores|  exit 0 # MUTANTE\n  reporta "GATE - tabela de adaptadores|' "$ORIG"

cp -f "$TMP/orig.sh" "$ORIG"
echo
echo "================ mortos=$P  sobreviventes=$F ================"
if [ "$F" -eq 0 ] && [ "$P" -gt 0 ]; then echo "mutacao verde: a suite detecta a perda de cada garantia"; exit 0
else echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
