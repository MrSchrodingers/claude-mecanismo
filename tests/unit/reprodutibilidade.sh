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
LC_ALL=C           bash install/manifest.sh "$T/c.lock"      >/dev/null
LC_ALL=en_US.UTF-8 bash install/manifest.sh "$T/utf.lock"    >/dev/null
LC_ALL=pt_BR.UTF-8 bash install/manifest.sh "$T/br.lock"     >/dev/null
chk "C == en_US.UTF-8" "$(cmp -s "$T/c.lock" "$T/utf.lock" && echo sim || echo nao)" "sim"
chk "C == pt_BR.UTF-8" "$(cmp -s "$T/c.lock" "$T/br.lock" && echo sim || echo nao)" "sim"

echo "== R2. o manifesto e invariante sob ordem de leitura do filesystem =="
# Duas geracoes seguidas no mesmo estado devem coincidir byte a byte.
bash install/manifest.sh "$T/a.lock" >/dev/null; bash install/manifest.sh "$T/b.lock" >/dev/null
chk "duas geracoes coincidem" "$(cmp -s "$T/a.lock" "$T/b.lock" && echo sim || echo nao)" "sim"

echo "== R3. o manifesto committado reflete a arvore =="
bash install/manifest.sh "$T/now.lock" >/dev/null
chk "manifest.lock esta atualizado" "$(cmp -s install/manifest.lock "$T/now.lock" && echo sim || echo nao)" "sim"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=4
[ "$P" -ne "$EXPECTED" ] && { echo "CONTAGEM INESPERADA: $P/$EXPECTED"; exit 1; }
[ "$F" -eq 0 ] && echo "reprodutibilidade verde ($P/$EXPECTED)" || echo "reprodutibilidade VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
