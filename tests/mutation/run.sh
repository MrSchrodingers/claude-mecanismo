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

# BASELINE: sem isto, uma regressao quebrada por ambiente faria TODOS os mutantes parecerem
# mortos - o runner reportaria verde justamente quando nao esta testando nada.
echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; P=$((P+1))
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

mutante(){ # $1=nome  $2=descricao  $3=caso-alvo que DEVE reprovar  $4..=comandos sed
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.sh" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao do sed nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if ! bash -n "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao (sed casou mal)"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  local out; out="$(bash "$REG" 2>&1)"
  if [ $? -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*$alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    # Suite reprovou, mas nao pelo caso que protege esta garantia: kill por acidente.
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao do gate: cada garantia removida DEVE quebrar a regressao =="

# M1 - cache aceita qualquer veredito, nao so `pass` (era o false-green do throttle)
mutante M1 "so veredito 'pass' e reutilizavel" "CONTINUA barrando" \
  sed -i 's/= "pass" \]; then/= "pass" ] || true; then/' "$ORIG"

# M2 - avisar por stderr+exit 0 em vez de additionalContext (canal inerte, ADR 0021)
mutante M2 "additionalContext como canal de aviso" "additionalContext" \
  sed -i 's|^aviso(){ jq -cn|aviso(){ printf "%s\\n" "$1" >\&2; exit 0; }\nunused_aviso(){ jq -cn|' "$ORIG"

# M3 - identidade por NOME em vez de bytes (nao ve conteudo de untracked)
mutante M3 "identidade sobre bytes do arquivo" "untracked reprova" \
  sed -i 's|printf .%s %s\\n. "$f" "$(sha256sum "$ROOT/$f" 2>/dev/null \| cut -d. . -f1)"|printf "%s\\n" "$f"|' "$ORIG"

# M4 - para no primeiro adaptador aplicavel (ponto cego de monorepo)
mutante M4 "conjuncao sobre TODOS os adaptadores" "nao mascara" \
  sed -i 's|^      break$|      break 2|' "$ORIG"

# M5 - tabela ausente sai 0 em silencio (inercia silenciosa)
mutante M5 "fail-closed quando a tabela some" "tabela vazia BARRA" \
  sed -i 's|^  reporta "GATE - tabela de adaptadores|  exit 0 # MUTANTE\n  reporta "GATE - tabela de adaptadores|' "$ORIG"

# M6 - dependencia estrutural ausente volta a sair 0 em silencio (G9)
mutante M6 "jq ausente e lacuna, nao sucesso" "sem jq em repo git" \
  sed -i 's|^    printf .%s. "$INPUT" . grep -q ..stop_hook_active|    exit 0 # MUTANTE\n    printf "%s" "$INPUT" \| grep -q '"'"'"stop_hook_active|' "$ORIG"

# M7 - adaptador que executa codigo do repo volta a rodar em auto-deteccao (G10)
mutante M7 "executor nao roda em auto-deteccao" "o motivo e EXECUTAR" \
  sed -i 's|if \[ "$(jq -r ..declared_effects.executes_repository_code // false. "$a")" = "true" \]; then|if false; then|' "$ORIG"

# M8 - env digest volta a ser so o caminho do binario (G11)
mutante M8 "env digest cobre o binario" "invalida o cache" \
  sed -i 's#"$c" "$rp" "$bh" "$vs"#"$c" "$pth" "" ""#' "$ORIG"

cp -f "$TMP/orig.sh" "$ORIG"
echo
echo "================ mortos=$P  sobreviventes=$F ================"
if [ "$F" -eq 0 ] && [ "$P" -gt 0 ]; then echo "mutacao verde: a suite detecta a perda de cada garantia"; exit 0
else echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
