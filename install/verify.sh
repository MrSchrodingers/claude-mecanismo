#!/usr/bin/env bash
# CONFORMIDADE: o que esta instalado e o que o manifesto declara sao a mesma coisa?
#
# Este arquivo e a resposta ao achado que subordinou todos os outros: o repositorio descrevia
# um sistema e a maquina rodava outro. Hooks nao versionados, agentes ausentes do repo e um
# verify-gate uma versao atras - por tres meses, sem sinal. Nao havia operacao de conferir.
#
# Colunas do relatorio, conforme o contrato acordado:
#   desired    o manifesto declara
#   installed  existe no disco com o mesmo digest
#   governed   sob qual autoridade foi carregado (user = gravavel pelo ator)
#
# `governed=user` NAO e um erro: e o estado atual e declarado desta fase. Componente correto
# carregado de origem gravavel tem integridade momentanea, nao autoridade. A fase seguinte
# move a politica para managed settings; ate la, isto fica visivel em vez de implicito.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
MAN="${1:-install/manifest.lock}"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
[ -f "$MAN" ] || { echo "manifesto ausente: $MAN (rode install/manifest.sh)"; exit 2; }

OK=0; DRIFT=0; MISSING=0; EXTRA=0
declare -A ESPERADO

while IFS=$'\t' read -r tipo origem destino digest; do
  case "$tipo" in ''|'#'*) continue;; esac
  ESPERADO["$destino"]=1
  alvo="$DEST/$destino"
  if [ ! -e "$alvo" ]; then
    printf '  AUSENTE   %-42s (declarado, nao instalado)\n' "$destino"; MISSING=$((MISSING+1)); continue
  fi
  if [ -d "$alvo" ]; then
    # O MANIFESTO e a autoridade, tambem para diretorio. Comparar instalado contra a working
    # tree deixava o manifesto fora do circuito: repo drift passava despercebido localmente.
    atual="$(cd "$alvo" && find . -type f -exec sha256sum {} + 2>/dev/null | sort -k2 | sha256sum | cut -c1-64)"
    esper="$digest"
    fonte="$(cd "$origem" && find . -type f -exec sha256sum {} + 2>/dev/null | sort -k2 | sha256sum | cut -c1-64)"
    if [ "$fonte" != "$digest" ]; then
      printf '  REPO-DRIFT %-40s (working tree != manifesto; rode install/manifest.sh)\n' "$destino"; DRIFT=$((DRIFT+1)); continue
    fi
  else
    atual="$(sha256sum "$alvo" 2>/dev/null | cut -c1-64)"; esper="$digest"
  fi
  if [ "$atual" = "$esper" ]; then OK=$((OK+1))
  else printf '  DIVERGE   %-42s (instalado != manifesto)\n' "$destino"; DRIFT=$((DRIFT+1)); fi
done < "$MAN"

# Componente ATIVO que o manifesto nao conhece: e o modo de falha original deste repo.
for d in hooks agents; do
  [ -d "$DEST/$d" ] || continue
  for f in "$DEST/$d"/*; do
    [ -e "$f" ] || continue
    rel="$d/$(basename "$f")"
    [ -n "${ESPERADO[$rel]:-}" ] || { printf '  ORFAO     %-42s (roda, nao esta no manifesto)\n' "$rel"; EXTRA=$((EXTRA+1)); }
  done
done
for f in "$DEST"/skills/*/; do
  [ -d "$f" ] || continue
  rel="skills/$(basename "${f%/}")"
  [ -n "${ESPERADO[$rel]:-}" ] || { printf '  ORFAO     %-42s (roda, nao esta no manifesto)\n' "$rel"; EXTRA=$((EXTRA+1)); }
done

TOT=$((OK+DRIFT+MISSING))
echo
printf 'conformidade: %s/%s ok | %s divergentes | %s ausentes | %s orfaos\n' "$OK" "$TOT" "$DRIFT" "$MISSING" "$EXTRA"
if [ $((DRIFT+MISSING+EXTRA)) -eq 0 ]; then
  echo "ESTADO: conforme (governed=user - politica ainda gravavel pelo ator, ver docs/adr/0022)"; exit 0
else
  echo "ESTADO: DIVERGENTE - o que roda nao e o que o repositorio declara."; exit 1
fi
