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
# TERMINOLOGIA: isto compra AUDITABILIDADE, nao reprodutibilidade. `ubuntu-24.04` fixa a familia
# da imagem, nao seu digest, e `apt-get update` consulta o estado corrente do repositorio: duas
# execucoes em datas diferentes podem instalar versoes diferentes. Registrar as versoes permite
# saber DEPOIS o que rodou; nao torna o build hermetico. Hermeticidade exigiria container por
# digest ou snapshot de repositorio apt - fase posterior.
# apt no runner nao tem pinagem estavel: fixar a versao quebra quando a imagem atualiza. O
# honesto e registrar a excecao no proprio workflow, para que ela seja uma decisao visivel e
# nao um esquecimento indistinguivel dos outros.
if grep -qE "apt-get.*install" "$WF"/*.yml 2>/dev/null; then
  chk "a excecao do apt esta justificada por escrito" \
      "$(awk '/- name:/{blk=""} {blk=blk $0 "\n"} /apt-get.*install/{print blk; exit}' "$WF"/*.yml | grep -qi "EXCECAO DECLARADA" && echo sim || echo nao)" "sim"
fi

echo "== S5. a CI instala versao COMPATIVEL com o que os adaptadores declaram =="
# Antes so conferia o NOME: `pandas>=2.2` declarado com `pandas==1.5.0` instalado passava,
# porque o constraint era removido com sed antes de comparar. Presenca nao e compatibilidade.
# PRE-REQUISITO DE ORACULO, nao capacidade opcional: sem `packaging` esta assercao nao pode
# ser avaliada, e a suite inteira precisa reprovar. Ausencia de oraculo e NAO VERIFICADO.
if ! python3 -c "import packaging.requirements" 2>/dev/null; then
  echo "  DEPENDENCIA DE ORACULO AUSENTE: python3-packaging."
  echo "  Sem ela S5 nao pode comparar versao instalada com specifier declarado."
  echo "  Estado: NAO VERIFICADO - a suite nao foi realizada."
  exit 2
fi
S5="$(python3 - <<'PY'
import glob, json, re, sys
from packaging.requirements import Requirement
from packaging.version import Version
inst = {}
for wf in glob.glob(".github/workflows/*.yml"):
    for line in open(wf):
        if "pip install" not in line: continue
        for tok in re.findall(r"'([^']+)'", line):
            if "==" in tok:
                n, v = tok.split("==", 1); inst[n.lower()] = v
prob = []
for a in glob.glob("execution/adapters/documents/*.json"):
    for raw in (json.load(open(a)).get("requires") or {}).get("python_packages", []):
        r = Requirement(raw); n = r.name.lower()
        if n not in inst: prob.append(f"{r.name}: declarado, NAO instalado pela CI"); continue
        if r.specifier and not r.specifier.contains(Version(inst[n]), prereleases=True):
            prob.append(f"{r.name}: CI instala {inst[n]}, incompativel com '{r.specifier}'")
print("OK" if not prob else "; ".join(prob))
PY
)"
chk "versao instalada satisfaz o specifier declarado" "$S5" "OK"

echo "== S6. a dependencia do proprio ORACULO tambem e pinada na CI =="
# Sem isto, S5 e obrigatorio localmente e indefinido no ambiente remoto - a garantia teria uma
# fronteira onde nao se aplica, que e o mesmo defeito com outra forma.
chk "packaging pinado no workflow" \
    "$(grep -h "pip install" "$WF"/*.yml | grep -q "'packaging==" && echo sim || echo nao)" "sim"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=6   # invariante FIXO: nenhum caso pode sumir reduzindo o esperado
if [ "$P" -ne "$EXPECTED" ]; then echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED"; exit 1; fi
[ "$F" -eq 0 ] && echo "cadeia de suprimentos verde ($P/$EXPECTED)" || echo "cadeia de suprimentos VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
