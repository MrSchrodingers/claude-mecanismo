#!/usr/bin/env bash
# Mutacao do INSTALADOR. Alvo separado porque a garantia nao vive no gate.
#
# Existe porque a convergencia (`--prune`) foi adicionada e QUEBROU o modo --dry-run: o
# `rm -rf` rodava antes da checagem de DRY. Medido: o dry-run apagou um componente e o digest
# do HOME voltou ao estado anterior. Garantia nova que quebra modo existente e o padrao que
# este projeto persegue - logo precisa de mutante proprio.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ORIG="install/apply.sh"; REG="tests/unit/regressao-gate.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0; EXPECTED_MUTANTS=1

echo "== baseline =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; else echo "  FAIL  baseline vermelho; abortando"; exit 1; fi

echo "== mutacao do instalador =="
# MI1: o portao do dry-run vira filtro - volta a cair na etapa de convergencia
cp -f "$TMP/orig.sh" "$ORIG"
sed -i 's|^if \[ "$DRY" -eq 1 \]; then$|if false; then|' "$ORIG"
if cmp -s "$TMP/orig.sh" "$ORIG"; then
  echo "  FAIL  MI1 NAO FOI APLICADO (padrao nao casa)"; F=$((F+1))
elif ! bash -n "$ORIG" 2>/dev/null; then
  echo "  FAIL  MI1 nao compila"; F=$((F+1))
else
  out="$(bash "$REG" 2>&1)"
  if [ $? -eq 0 ]; then echo "  FAIL  MI1 SOBREVIVEU - dry-run destrutivo passa despercebido"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*orfao continua no disco\|FAIL.*estado identico"; then
    echo "  PASS  MI1 morto pelo caso certo (G10)"; P=$((P+1))
  else echo "  FAIL  MI1: reprovou, mas nao em G10 - kill nao atribuivel"; F=$((F+1)); fi
fi
cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'mutantes_esperados=%s  mortos=%s  falhas=%s\n' "$EXPECTED_MUTANTS" "$P" "$F"
if [ "$F" -eq 0 ] && [ "$P" -eq "$EXPECTED_MUTANTS" ]; then echo "mutacao do instalador verde"; exit 0
else echo "mutacao do instalador VERMELHA"; exit 1; fi
