#!/usr/bin/env bash
# Mutacao dos instaladores. Cada mutante deve atacar uma garantia existente
# e morrer por um oraculo atribuivel a essa mesma propriedade.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

ORIG="install/apply.sh"
ORIG_M="install/apply-managed.sh"
REG="tests/unit/regressao-gate.sh"
REG_TX="tests/unit/managed-transaction.sh"
TMP="$(mktemp -d)"
trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null; cp -f "$TMP/orig-managed.sh" "$ORIG_M" 2>/dev/null; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
cp -f "$ORIG_M" "$TMP/orig-managed.sh"

P=0
F=0
EXPECTED_MUTANTS=3

restore_common(){ cp -f "$TMP/orig.sh" "$ORIG"; }
restore_managed(){ cp -f "$TMP/orig-managed.sh" "$ORIG_M"; }

kill_ok(){ echo "  PASS  $1"; P=$((P+1)); }
kill_fail(){ echo "  FAIL  $1"; F=$((F+1)); }

echo "== baseline =="
if bash "$REG" >/dev/null 2>&1; then
  echo "  PASS  regressao baseline verde"
else
  echo "  FAIL  regressao baseline vermelha; abortando"
  exit 1
fi
if bash "$REG_TX" >/dev/null 2>&1; then
  echo "  PASS  transacao managed baseline verde"
else
  echo "  FAIL  transacao managed baseline vermelha; abortando"
  exit 1
fi

echo "== MI1. dry-run nao pode atravessar o portao de escrita =="
restore_common
sed -i 's|^if \[ "$DRY" -eq 1 \]; then$|if false; then|' "$ORIG"
if cmp -s "$TMP/orig.sh" "$ORIG"; then
  kill_fail "MI1 NAO FOI APLICADO (ancora ausente)"
elif ! bash -n "$ORIG" 2>/dev/null; then
  kill_fail "MI1 nao compila"
else
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    kill_fail "MI1 SOBREVIVEU - dry-run destrutivo passou despercebido"
  elif printf '%s' "$out" | grep -q "FAIL.*orfao continua no disco\|FAIL.*estado identico"; then
    kill_ok "MI1 morto pelo caso de dry-run destrutivo"
  else
    kill_fail "MI1 reprovou por causa nao atribuivel ao dry-run"
  fi
fi
restore_common

echo "== MI2. falha do legado deve restaurar o estado anterior =="
restore_managed
python3 - "$ORIG_M" <<'PYM'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
alvo = 'if [ "$rc" -ne 0 ]; then rollback && exit "$rc" || exit 70; fi'
if s.count(alvo) != 1:
    sys.exit("ANCORA MI2 NAO CASOU (%d ocorrencias)" % s.count(alvo))
s = s.replace(alvo, 'if [ "$rc" -ne 0 ]; then exit "$rc"; fi  # MUTANTE: omite rollback')
open(p, "w", encoding="utf-8").write(s)
PYM
if cmp -s "$TMP/orig-managed.sh" "$ORIG_M"; then
  kill_fail "MI2 NAO FOI APLICADO"
elif ! bash -n "$ORIG_M" 2>/dev/null; then
  kill_fail "MI2 nao compila"
else
  out="$(bash "$REG_TX" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    kill_fail "MI2 SOBREVIVEU - falha managed deixou estado alterado sem sinal"
  elif printf '%s' "$out" | grep -q "FAIL first-deploy-tree\|FAIL first-deploy-policy\|FAIL existing-tree\|FAIL existing-policy"; then
    kill_ok "MI2 morto pela propriedade de restauracao transacional"
  else
    kill_fail "MI2 reprovou por causa nao atribuivel ao rollback"
    printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/        /'
  fi
fi
restore_managed

echo "== MI3. permissao insegura deve reprovar e desfazer o deployment =="
restore_managed
python3 - "$ORIG_M" <<'PYM'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
alvo = 'if [ -n "$unsafe" ]; then echo "permissão insegura: $unsafe" >&2; rollback && exit 1 || exit 70; fi'
if s.count(alvo) != 1:
    sys.exit("ANCORA MI3 NAO CASOU (%d ocorrencias)" % s.count(alvo))
s = s.replace(alvo, 'if false; then echo "permissão insegura: $unsafe" >&2; rollback && exit 1 || exit 70; fi  # MUTANTE')
open(p, "w", encoding="utf-8").write(s)
PYM
if cmp -s "$TMP/orig-managed.sh" "$ORIG_M"; then
  kill_fail "MI3 NAO FOI APLICADO"
elif ! bash -n "$ORIG_M" 2>/dev/null; then
  kill_fail "MI3 nao compila"
else
  out="$(bash "$REG_TX" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    kill_fail "MI3 SOBREVIVEU - permissao insegura foi aceita"
  elif printf '%s' "$out" | grep -q "FAIL unsafe-rc\|FAIL unsafe-cleanup"; then
    kill_ok "MI3 morto pela verificacao objetiva de permissao"
  else
    kill_fail "MI3 reprovou por causa nao atribuivel a permissao"
    printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/        /'
  fi
fi
restore_managed

echo
printf 'mutantes_esperados=%s  mortos=%s  falhas=%s\n' "$EXPECTED_MUTANTS" "$P" "$F"
if [ "$F" -eq 0 ] && [ "$P" -eq "$EXPECTED_MUTANTS" ]; then
  echo "mutacao do instalador verde"
  exit 0
fi
echo "mutacao do instalador VERMELHA"
exit 1
