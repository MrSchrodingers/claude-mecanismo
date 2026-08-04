#!/usr/bin/env bash
# Teste METAMORFICO: propriedades que o manifesto deve preservar sob transformacoes que nao
# alteram o conteudo. Nao ha oraculo para "qual e o digest certo" - ha relacoes invariantes.
#
# Existe porque a CI reprovou tres commits seguidos enquanto a suite local estava verde: o
# digest de diretorio dependia do locale de `sort`. A suite local nao podia detectar, por rodar
# sempre no mesmo locale. Este e o caso: teste local e teste independente medem coisas diferentes.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "== R1. o manifesto e invariante sob LOCALE =="
# ARMADILHA JA PAGA, DUAS VEZES:
#  (a) pedir LC_ALL=pt_BR.UTF-8 sem esse locale instalado nao muda nada - o shell avisa e segue
#      no anterior, e a assercao "C == pt_BR" comparava C consigo mesmo: vacuamente verdadeira;
#  (b) conferir com `locale` tambem nao serve - `LC_ALL=xx_YY.UTF-8 locale` ECOA "xx_YY.UTF-8"
#      para um locale inexistente. Verificar o nome nao verifica o efeito.
# O discriminador precisa ser COMPORTAMENTAL: o locale so importa se muda a ordenacao. Sentinela
# usada e o par que causou o defeito original (SKILL.md vs references/), onde C e UTF-8 diferem.
ordena_como_C(){ [ "$(printf 'SKILL.md\nreferences/a.md\n' | LC_ALL="$1" sort | head -1)" = "SKILL.md" ]; }

LC_ALL=C bash install/manifest.sh "$T/c.lock" >/dev/null
NAO_C=0
for loc in en_US.UTF-8 pt_BR.UTF-8 de_DE.UTF-8 C.UTF-8; do
  if ordena_como_C "$loc"; then
    echo "  SKIP  $loc (indisponivel ou ordena como C - nada a exercitar)"; continue
  fi
  LC_ALL="$loc" bash install/manifest.sh "$T/l.lock" >/dev/null
  chk "C == $loc (ordenacao comprovadamente distinta de C)" \
      "$(cmp -s "$T/c.lock" "$T/l.lock" && echo sim || echo nao)" "sim"
  NAO_C=$((NAO_C+1))
done
# Sem isto, um ambiente sem nenhum locale alternativo daria suite verde sem exercitar a
# propriedade - que e a forma vacua deste mesmo teste.
chk "ao menos um locale de ordenacao distinta foi exercitado" "$([ "$NAO_C" -ge 1 ] && echo sim || echo nao)" "sim"
EXPECTED=$((NAO_C + 8))   # locais exercitados + a exigencia acima + R4(4 fontes/locales + 1
                          # discriminador) + R2 + R3. Invariante: caso que some REPROVA.

echo "== R4. o contrato de subagente e invariante ao locale =="
# Reproduzido: `y/.../.../` opera sobre caracteres e sob LC_ALL=C o sed processa bytes, entao a
# normalizacao de acentos nao acontecia e o hook barrava retorno legitimo em PT-BR. O defeito do
# ADR 0018 reaparecendo por outra via - agora dependente do ambiente, nao do padrao.
#
# ESTA VERSAO DE R4 CORRIGE UMA R4 VACUA (2026-08-04, sexta instancia do padrao). A anterior
# montava o payload com `transcript_path` e `subagent_type`; o hook le `agent_type` e
# `last_assistant_message`/`agent_transcript_path`. Com `agent_type` vazio, o hook saia no
# ramo `*) exit 0` do filtro de tipo e NUNCA chegava a normalizacao que R4 dizia proteger.
# Provado por mutacao: removida toda a normalizacao, a R4 antiga seguia verde (exit 0 nos dois
# locales); com os campos corretos, o mesmo mutante morre (exit 2 nos dois).
#   precondicao falha -> operacao nao executa -> pos-condicao vacuamente verdadeira -> VERDE
# As duas defesas contra a recaida: os campos vem do payload REAL capturado pela sonda, e o
# caso R4e obriga o oraculo a DISCRIMINAR - sem ele, exit 0 nao distingue aprovacao de inercia.
CONTRATO="$PWD/evidence/hooks/subagent-contract.sh"
RET='RESULTADO: corrigido.
EVIDÊNCIA: verify.sh:12, `bash x.sh` exit=0
RISCOS-PENDÊNCIAS: nenhuma
PROPAGAÇÃO: nenhuma'
# Fonte 1 - campo dedicado, que e o que o runtime entrega de fato (medido na sonda).
paga_msg(){ jq -nc --arg m "$1" '{hook_event_name:"SubagentStop",agent_type:"tdd",last_assistant_message:$m}'; }
# Fonte 2 - fallback pelo transcript DO SUBAGENTE. Sem exercitar as duas, metade do caminho
# de leitura fica sem cobertura.
TR="$T/tr.jsonl"
python3 - "$TR" "$RET" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"type":"assistant","message":{"role":"assistant",
    "content":[{"type":"text","text":sys.argv[2]}]}}) + "\n")
PY
paga_tr(){ jq -nc --arg p "$1" '{hook_event_name:"SubagentStop",agent_type:"tdd",agent_transcript_path:$p}'; }

for L in C en_US.UTF-8; do
  rc=$(paga_msg "$RET" | LC_ALL="$L" bash "$CONTRATO" >/dev/null 2>&1; echo $?)
  chk "retorno acentuado ACEITO sob LC_ALL=$L (fonte: last_assistant_message)" "$rc" 0
  rc=$(paga_tr "$TR" | LC_ALL="$L" bash "$CONTRATO" >/dev/null 2>&1; echo $?)
  chk "retorno acentuado ACEITO sob LC_ALL=$L (fonte: agent_transcript_path)" "$rc" 0
done
# R4e - DISCRIMINADOR. Mesma forma de payload, conteudo sem ancora: precisa REPROVAR. Se este
# caso passar a dar 0, os quatro acima voltaram a ser vacuos e a suite tem de gritar.
SEM='RESULTADO: revisei e esta correto.
EVIDÊNCIA: li com atenção e não encontrei problema.
RISCOS: nenhum.
PROPAGAÇÃO: nenhuma.'
rc=$(paga_msg "$SEM" | LC_ALL=C bash "$CONTRATO" >/dev/null 2>&1; echo $?)
chk "  o oraculo DISCRIMINA (retorno sem ancora reprova)" "$rc" 2

echo "== R2. o manifesto e invariante sob ordem de leitura do filesystem =="
# Duas geracoes seguidas no mesmo estado devem coincidir byte a byte.
bash install/manifest.sh "$T/a.lock" >/dev/null; bash install/manifest.sh "$T/b.lock" >/dev/null
chk "duas geracoes coincidem" "$(cmp -s "$T/a.lock" "$T/b.lock" && echo sim || echo nao)" "sim"

echo "== R3. o manifesto committado reflete a arvore =="
bash install/manifest.sh "$T/now.lock" >/dev/null
chk "manifest.lock esta atualizado" "$(cmp -s install/manifest.lock "$T/now.lock" && echo sim || echo nao)" "sim"

echo
echo "================ PASS=$P  FAIL=$F ================"

[ "$P" -ne "$EXPECTED" ] && { echo "CONTAGEM INESPERADA: $P/$EXPECTED"; exit 1; }
[ "$F" -eq 0 ] && echo "reprodutibilidade verde ($P/$EXPECTED)" || echo "reprodutibilidade VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
