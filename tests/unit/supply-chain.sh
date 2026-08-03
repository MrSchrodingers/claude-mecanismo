#!/usr/bin/env bash
# CADEIA DE SUPRIMENTOS do gate externo. Toda dependencia que a CI executa precisa ser pinada.
#
# Existe porque eu reintroduzi o defeito depois de corrigi-lo: numa rodada pinei checkout, ruff,
# pandas e openpyxl; na seguinte adicionei `pymupdf` sem versao. Terceira ocorrencia da mesma
# classe na mesma sessao (adaptador .NET declarado errado, pandas nao declarado, pymupdf nao
# pinado). Regra enunciada nao e regra executada - por isso ela vira teste.
#
# Tag e MUTAVEL: `actions/checkout@v4` pode apontar para outro commit amanha. Numa fronteira que
# decide se um artefato atravessa, a entrada precisa ser identificavel, nao apenas nomeada.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
WF=".github/workflows"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

echo "== S1. toda action e pinada por SHA completo, nunca por tag =="
BAD=""
while IFS= read -r line; do
  ref="${line#*uses: }"; ref="${ref%% *}"
  case "$ref" in
    */*@[0-9a-f]*) sha="${ref##*@}"
      [ "${#sha}" -eq 40 ] || BAD="$BAD $ref" ;;
    */*@*) BAD="$BAD $ref" ;;
  esac
done < <(grep -h "uses:" "$WF"/*.yml 2>/dev/null)
chk "nenhuma action por tag ou SHA curto" "${BAD:-nenhuma}" "nenhuma"

echo "== S2. todo pacote pip tem versao exata =="
BAD=""
while IFS= read -r pkg; do
  case "$pkg" in *==*) ;; *) BAD="$BAD $pkg";; esac
done < <(grep -h "pip install" "$WF"/*.yml 2>/dev/null | tr ' ' '\n' | grep "^'" | tr -d "'")
chk "nenhum pacote pip sem ==" "${BAD:-nenhum}" "nenhum"

echo "== S3. o runner e uma imagem nomeada, nao 'latest' =="
chk "runs-on nao usa -latest" \
    "$(grep -h "runs-on:" "$WF"/*.yml | grep -c -- "-latest" | tr -d ' ')" "0"

echo "== S4. dependencia de sistema NAO pinada e DECLARADA, nao silenciosa =="
# apt no runner nao tem pinagem estavel: fixar a versao quebra quando a imagem atualiza. O
# honesto e registrar a excecao no proprio workflow, para que ela seja uma decisao visivel e
# nao um esquecimento indistinguivel dos outros.
if grep -q "apt-get install" "$WF"/*.yml 2>/dev/null; then
  chk "a excecao do apt esta justificada por escrito" \
      "$(grep -B10 -A1 "apt-get install" "$WF"/*.yml | grep -qi "EXCECAO DECLARADA" && echo sim || echo nao)" "sim"
fi

echo "== S5. as versoes pip da CI batem com as declaradas pelos adaptadores =="
# O adaptador declara o que precisa; a CI instala. Divergencia entre os dois significa que a
# suite valida um ambiente que o adaptador nao pede - ou o contrario.
DECL="$(jq -r '.requires.python_packages[]? // empty' execution/adapters/documents/*.json 2>/dev/null | sed 's/[<>=].*//' | sort -u)"
MISS=""
for d in $DECL; do
  grep -h "pip install" "$WF"/*.yml | grep -q "'$d==" || MISS="$MISS $d"
done
chk "todo pacote declarado por adaptador e instalado pela CI" "${MISS:-nenhum}" "nenhum"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=5
if [ "$P" -ne "$EXPECTED" ]; then echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED"; exit 1; fi
[ "$F" -eq 0 ] && echo "cadeia de suprimentos verde ($P/$EXPECTED)" || echo "cadeia de suprimentos VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
