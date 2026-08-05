#!/usr/bin/env bash
# Mutacao do INSTALADOR. Alvo separado porque a garantia nao vive no gate.
#
# Existe porque a convergencia (`--prune`) foi adicionada e QUEBROU o modo --dry-run: o
# `rm -rf` rodava antes da checagem de DRY. Medido: o dry-run apagou um componente e o digest
# do HOME voltou ao estado anterior. Garantia nova que quebra modo existente e o padrao que
# este projeto persegue - logo precisa de mutante proprio.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
ORIG="install/apply.sh"; REG="tests/unit/regressao-gate.sh"
# SEGUNDO ALVO: o instalador MANAGED, cuja garantia vive em outra suite. Sao arquivos e
# propriedades distintos - misturar os dois num unico par (ORIG, REG) faria um mutante do managed
# ser cobrado contra a regressao do gate, e o kill nunca seria atribuivel.
ORIG_M="install/apply-managed.sh"; REG_M="tests/unit/managed.sh"
TMP="$(mktemp -d)"
trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null; cp -f "$TMP/orig-managed.sh" "$ORIG_M" 2>/dev/null; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
cp -f "$ORIG_M" "$TMP/orig-managed.sh"
P=0; F=0; EXPECTED_MUTANTS=3

echo "== baseline =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; else echo "  FAIL  baseline vermelho; abortando"; exit 1; fi
if ! bash "$REG_M" >/dev/null 2>&1; then echo "  FAIL  baseline do managed vermelho; abortando"; exit 1; fi

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

echo "== mutacao do instalador managed =="
# MI2: a publicacao volta a acontecer ANTES dos portoes - o defeito que a auditoria externa
# encontrou. A arvore ativa passa a ser reescrita antes de qualquer checagem, e um deploy
# reprovado a deixa parcialmente atualizada.
#
# ESCOLHA DO MUTANTE. O caminho obvio - `STAGE="$OPT"` - reprovaria tambem o DEPLOY BEM-SUCEDIDO
# (a conformidade passaria a olhar uma arvore que a publicacao ja moveu), e MG15 morreria na sua
# propria precondicao, nao na propriedade. Este mutante mantem o caminho de sucesso intacto e
# ataca exatamente a ordem escrita-versus-portao, que e a garantia sob teste.
cp -f "$TMP/orig-managed.sh" "$ORIG_M"
python3 - "$ORIG_M" <<'PYM'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
alvo = 'if [ "$REAL" -eq 1 ]; then chown -R root:root "$STAGE" || exit 1; fi'
if s.count(alvo) != 1:
    sys.exit("ANCORA NAO CASOU (%d ocorrencias)" % s.count(alvo))
open(p, "w", encoding="utf-8").write(s.replace(
    alvo, alvo + '\nrm -rf "$OPT"; cp -a "$STAGE" "$OPT"   # MUTANTE: publica ANTES dos portoes'))
PYM
if cmp -s "$TMP/orig-managed.sh" "$ORIG_M"; then
  echo "  FAIL  MI2 NAO FOI APLICADO (padrao nao casa)"; F=$((F+1))
elif ! bash -n "$ORIG_M" 2>/dev/null; then
  echo "  FAIL  MI2 nao compila"; F=$((F+1))
else
  out="$(bash "$REG_M" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  MI2 SOBREVIVEU - deploy reprovado altera a arvore ativa sem sinal"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*BYTE A BYTE identica"; then
    echo "  PASS  MI2 morto pelo caso certo (MG15)"; P=$((P+1))
  else
    echo "  FAIL  MI2: reprovou, mas nao em MG15 - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
fi
cp -f "$TMP/orig-managed.sh" "$ORIG_M"

# MI3: o material de rollback e descartado ASSIM QUE a arvore e publicada, antes de a politica
# estar instalada. E exatamente o defeito que a revisao independente do PR #5 encontrou: a
# propriedade publicada era `DeployFail => ActiveState inalterado`, e o codigo so a entregava
# para falhas ANTERIORES a publicacao. Depois dela, `mktemp`, `jq`, `cp`, `chmod` e `chown`
# rodavam sem retorno verificado e sem nada para desfazer.
#
# MI2 nao cobre isto: ele move a publicacao para ANTES dos portoes, e morre em MG15. Este mutante
# mantem a ordem correta e destroi so a capacidade de DESFAZER - por isso precisa do failpoint,
# que e o unico jeito de provocar a falha pos-publicacao de forma deterministica.
cp -f "$TMP/orig-managed.sh" "$ORIG_M"
python3 - "$ORIG_M" <<'PYM'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
alvo = '''if ! mv -f "$SET_NOVO" "$SETTINGS"; then'''
if s.count(alvo) != 1:
    sys.exit("ANCORA NAO CASOU (%d ocorrencias)" % s.count(alvo))
# descarta o rollback antes de instalar a politica
s = s.replace(alvo, 'rm -rf "$ANTERIOR" 2>/dev/null || true   # MUTANTE\n' + alvo)
open(p, "w", encoding="utf-8").write(s)
PYM
if cmp -s "$TMP/orig-managed.sh" "$ORIG_M"; then
  echo "  FAIL  MI3 NAO FOI APLICADO (padrao nao casa)"; F=$((F+1))
elif ! bash -n "$ORIG_M" 2>/dev/null; then
  echo "  FAIL  MI3 nao compila"; F=$((F+1))
else
  out="$(bash "$REG_M" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  MI3 SOBREVIVEU - falha pos-publicacao deixa o estado ativo alterado sem sinal"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*estado ativo INTEIRO volta ao anterior"; then
    echo "  PASS  MI3 morto pelo caso certo (MG17)"; P=$((P+1))
  else
    echo "  FAIL  MI3: reprovou, mas nao em MG17 - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
fi
cp -f "$TMP/orig-managed.sh" "$ORIG_M"

echo
printf 'mutantes_esperados=%s  mortos=%s  falhas=%s\n' "$EXPECTED_MUTANTS" "$P" "$F"
if [ "$F" -eq 0 ] && [ "$P" -eq "$EXPECTED_MUTANTS" ]; then echo "mutacao do instalador verde"; exit 0
else echo "mutacao do instalador VERMELHA"; exit 1; fi
