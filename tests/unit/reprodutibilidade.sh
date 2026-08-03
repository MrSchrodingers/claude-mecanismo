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
EXPECTED=$((NAO_C + 3))   # locais exercitados + a exigencia acima + R2 + R3

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
