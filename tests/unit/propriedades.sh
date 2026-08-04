#!/usr/bin/env bash
# TESTES DE PROPRIEDADE. Cada caso afirma uma propriedade que deve valer para uma FAMILIA de
# entradas geradas, nao para um exemplo escolhido a mao.
#
# POR QUE, neste repositorio especificamente. Os testes por exemplo daqui ja falharam duas vezes
# da mesma maneira: o exemplo casava com a implementacao, e a implementacao reconhecia a FORMA
# do exemplo em vez da propriedade. Foi assim que:
#   - o oraculo da ancora do contrato reconhecia `exit code 0` mas nao ``exit code `0` ``;
#   - a primeira versao de S2 tinha `\[\]` dentro da classe de caracteres, o que a invalidava,
#     e o `pymupdf` sem pinagem entrou por baixo dela.
# Um caso por exemplo prova que a implementacao aceita AQUELE exemplo. A propriedade e o que se
# queria garantir.
#
# ACHADOS NA PRIMEIRA EXECUCAO (2026-08-04) - dois detectores de seguranca furados:
#   S2 so enxergava tokens iniciados por ASPA SIMPLES. `pip install requests` e
#      `pip install "requests"` PASSAVAM: pacote sem pinagem atravessava o gate por diferenca
#      de formatacao. Era a propria classe que S2 existe para impedir.
#   S1 recortava por `${line#*uses: }`, com UM espaco literal. `uses:  a/b@v1` (dois espacos)
#      produzia string vazia e a action nao pinada passava batida.
# Nenhum dos dois seria encontrado por mais um caso por exemplo escrito por quem escreveu o
# detector - o exemplo herdaria a mesma suposicao de formatacao.
#
# DETERMINISMO: a semente e FIXA. Um teste de propriedade que muda de resultado entre execucoes
# transforma o gate em ruido, e ruido faz o operador desligar o gate. A semente e impressa; para
# explorar mais, `PROP_SEED=<n> PROP_ITER=<n> bash tests/unit/propriedades.sh`.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
REPO="$PWD"
SEED="${PROP_SEED:-20260804}"
ITER="${PROP_ITER:-6}"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
echo "semente=$SEED  iteracoes=$ITER"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/wf"

# ---------------------------------------------------------------------------------------------
# Roda a suite de cadeia de suprimentos sobre um workflow SINTETICO. E uma COPIA do workflow
# real com UMA linha trocada: assim S3..S6 continuam valendo e a reprovacao e atribuivel a
# linha alterada, e nao a um arquivo genericamente incompleto.
sc_caso(){ # $1=linha nova  $2=pip|act  -> ecoa PASS/FAIL do caso correspondente
  cp "$REPO/.github/workflows/verify.yml" "$T/wf/verify.yml"
  python3 - "$T/wf/verify.yml" "$1" "$2" <<'PY'
import re, sys
p, novo, tipo = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
pat, ind = ((r"^ *python3 -m pip install .*$", " " * 10) if tipo == "pip"
            else (r"^ *- uses: actions/checkout@.*$", " " * 6))
s2 = re.sub(pat, ind + novo, s, count=1, flags=re.M)
if s2 == s:
    sys.exit("ANCORA NAO CASOU - o caso mediria o workflow original")
open(p, "w").write(s2)
PY
  [ $? -eq 0 ] || { echo ANCORA; return; }
  local key out
  key=$([ "$2" = pip ] && echo 'nenhum pacote pip sem' || echo 'nenhuma action por tag')
  out="$(SUPPLY_CHAIN_WF_DIR="$T/wf" bash "$REPO/tests/unit/supply-chain.sh" 2>&1)"
  printf '%s' "$out" | grep -E "$key" | sed 's/^ *//' | cut -c1-4
}

echo "== PB1. o detector de pinagem pip nao depende de FORMATACAO =="
# Toda variante abaixo declara `requests` SEM versao exata. A propriedade: qualquer que seja a
# forma de escrever, o detector reprova.
i=0
for v in "requests" "'requests'" '"requests"' "'requests>=2.0'" "requests[socks]" "'requests~=2.0'"; do
  r="$(sc_caso "python3 -m pip install --quiet $v" pip)"
  chk "sem pinagem reprova: $v" "$r" "FAIL"; i=$((i+1))
done
# CONTROLES. Sem eles um detector que reprovasse SEMPRE passaria em todos os casos acima, e a
# suite mediria "reprova" em vez de "discrimina".
for v in "'requests==2.32.3'" 'requests==2.32.3' '"requests==2.32.3"'; do
  r="$(sc_caso "python3 -m pip install --quiet $v" pip)"
  chk "  pinado passa: $v" "$r" "PASS"
done

echo "== PB2. o detector de action nao pinada nao depende de FORMATACAO =="
SHA40="11d5960a326750d5838078e36cf38b85af677262"
for v in "- uses: actions/checkout@v4" \
         "- uses:  actions/checkout@v4" \
         "- uses:   actions/checkout@v4" \
         "- uses: actions/checkout@11d5960" \
         "- uses: actions/checkout@v4  # comentario"; do
  r="$(sc_caso "$v" act)"
  chk "nao pinada reprova: ${v#- }" "$r" "FAIL"
done
for v in "- uses: actions/checkout@$SHA40" "- uses:  actions/checkout@$SHA40"; do
  r="$(sc_caso "$v" act)"
  chk "  pinada por SHA de 40 passa: ${v#- }" "$r" "PASS"
done

echo "== PB3. nome de arquivo hostil e VALOR, nunca comando =="
# D1 diz que placeholders sao substituidos por VALOR e que nada e re-parseado. A propriedade:
# para QUALQUER nome de arquivo, nenhum efeito lateral do nome ocorre. O corpus cobre as formas
# que produziriam execucao se em algum ponto houvesse `sh -c` ou re-parse.
DT="$REPO/execution/document-tools/doctool.sh"
if ! command -v jq >/dev/null 2>&1; then
  echo "NAO VERIFICADO: jq ausente - doctool nao opera." >&2; exit 2
fi
HOSTIS_OK=0; HOSTIS_BAD=""
# O MARCADOR E RELATIVO, de proposito. A primeira versao deste caso embutia o caminho ABSOLUTO
# do marcador dentro do nome do arquivo - e nome de arquivo nao pode conter '/'. Resultado:
# 5 dos 10 nomes nem chegavam a ser criados, e a assercao "nenhum efeito lateral" seria
# verdadeira sobre arquivos que nunca existiram. E a forma vacua outra vez, agora no teste que
# eu estava escrevendo para caca-la. O discriminador de exercicio abaixo e o que a denuncia.
mkdir -p "$T/docs"
n=0
while IFS= read -r nome; do
  n=$((n+1))
  rm -f "$T/docs/PWNED_PROP" "$REPO/PWNED_PROP" "$T/PWNED_PROP"
  f="$T/docs/$nome"
  printf 'coluna_a,coluna_b\n1,2\n3,4\n' > "$f" 2>/dev/null || { HOSTIS_BAD="$HOSTIS_BAD [nao-criavel:$nome]"; continue; }
  ( cd "$T/docs" && DOC_ADAPTERS_DIR="$REPO/execution/adapters/documents" \
      timeout 60 bash "$DT" probe "$f" >/dev/null 2>&1 )
  # procura o marcador nos tres lugares onde uma execucao acidental o deixaria: o cwd do
  # doctool, a raiz do repositorio e o temporario da suite.
  if [ -e "$T/docs/PWNED_PROP" ] || [ -e "$REPO/PWNED_PROP" ] || [ -e "$T/PWNED_PROP" ]; then
    HOSTIS_BAD="$HOSTIS_BAD [EXECUTOU:$nome]"
  else
    HOSTIS_OK=$((HOSTIS_OK+1))
  fi
  rm -f "$f" "$T/docs/PWNED_PROP" "$REPO/PWNED_PROP" "$T/PWNED_PROP"
done <<'EOF'
$(touch PWNED_PROP).csv
`touch PWNED_PROP`.csv
; touch PWNED_PROP; .csv
| touch PWNED_PROP .csv
&& touch PWNED_PROP .csv
$(printf PWNED_PROP > PWNED_PROP).csv
nome com espacos.csv
--flag-parecida.csv
'aspas'simples.csv
"aspas"duplas.csv
EOF
chk "nenhum dos $n nomes hostis produziu efeito lateral" "${HOSTIS_BAD:-nenhum}" "nenhum"
# DISCRIMINADOR: sem esta assercao, um doctool que abortasse em TODO nome hostil (sem nunca
# processar nada) daria o mesmo resultado acima, e o caso seria vacuamente verdadeiro.
chk "  e o corpus foi de fato exercitado ($HOSTIS_OK/$n)" \
    "$([ "$HOSTIS_OK" -eq "$n" ] && echo sim || echo nao)" "sim"

echo "== PB4. a identidade do manifesto e INJETIVA sobre conteudo =="
# Propriedade: alterar UM byte de QUALQUER componente rastreado muda o manifesto. Se nao mudar,
# a identidade nao identifica - e foi assim que o repositorio pode divergir de ~/.claude em
# silencio por meses (ADR 0022).
CP="$T/repo"; mkdir -p "$CP"
tar -C "$REPO" -cf - --exclude=.git --exclude=.mypy_cache --exclude=.ruff_cache . 2>/dev/null | tar -C "$CP" -xf -
( cd "$CP" && bash install/manifest.sh "$T/base.lock" >/dev/null 2>&1 )
chk "manifesto de referencia gerado" "$([ -s "$T/base.lock" ] && echo sim || echo nao)" "sim"
MUDOU=0; IGUAL=""
ALVOS="$(cut -f2 "$T/base.lock" | grep -v '^#' | head -200)"
python3 - "$T/base.lock" "$SEED" "$ITER" > "$T/escolhidos" <<'PY'
import random, sys
lock, seed, it = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
alvos = [l.split("\t")[1] for l in open(lock) if not l.startswith("#") and "\t" in l]
r = random.Random(seed)
# amostra SEM reposicao: repetir o mesmo arquivo inflaria a contagem sem ampliar a cobertura
for a in r.sample(alvos, min(it, len(alvos))):
    print(a)
PY
while IFS= read -r rel; do
  alvo="$CP/$rel"
  [ -f "$alvo" ] || { alvo="$(find "$CP/$rel" -type f 2>/dev/null | head -1)"; }
  [ -f "$alvo" ] || continue
  cp "$alvo" "$T/bkp"
  printf '\n# byte de mutacao de propriedade\n' >> "$alvo"
  ( cd "$CP" && bash install/manifest.sh "$T/mut.lock" >/dev/null 2>&1 )
  if cmp -s "$T/base.lock" "$T/mut.lock"; then IGUAL="$IGUAL [$rel]"; else MUDOU=$((MUDOU+1)); fi
  cp "$T/bkp" "$alvo"
done < "$T/escolhidos"
ESCOLHIDOS=$(wc -l < "$T/escolhidos")
chk "toda mutacao de 1 componente mudou o manifesto ($MUDOU/$ESCOLHIDOS)" "${IGUAL:-nenhum}" "nenhum"
chk "  e houve mutacao a exercitar (nao vacuo)" \
    "$([ "$MUDOU" -ge 1 ] && echo sim || echo nao)" "sim"
( cd "$CP" && bash install/manifest.sh "$T/rest.lock" >/dev/null 2>&1 )
chk "  restaurado, o manifesto volta a ser identico" \
    "$(cmp -s "$T/base.lock" "$T/rest.lock" && echo sim || echo nao)" "sim"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=22
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED (semente=$SEED). Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "propriedades verde ($P/$EXPECTED)" || echo "propriedades VERMELHA (semente=$SEED)"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
