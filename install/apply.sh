#!/usr/bin/env bash
# INSTALADOR: repositorio -> ~/.claude, a partir do manifesto. Idempotente.
#
# Regra que este arquivo existe para tornar verdadeira: nao existe "instalar manualmente".
# `cp hook.sh ~/.claude` foi como o sistema divergiu do repositorio sem ninguem perceber.
# Aqui: manifesto -> installer -> verificador. Backup antes de qualquer escrita.
#
# ESCOPO DESTA FASE: escopo de usuario. A politica continua gravavel pelo ator governado -
# limitacao DECLARADA, nao resolvida. A fase 2 (managed settings root-owned +
# allowManagedHooksOnly) exige sudo e so deve rodar depois que todo hook estiver versionado,
# porque allowManagedHooksOnly desliga de uma vez todo hook de escopo de usuario.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
MAN="install/manifest.lock"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

[ -f "$MAN" ] || bash install/manifest.sh >/dev/null

# DRY-RUN E UM PORTAO, NAO UM FILTRO. A versao anterior filtrava a copia mas caia na etapa de
# convergencia e chegava a executar `rm -rf` antes de checar DRY - o modo anunciado como
# inspecao segura apagava componente. Medido: --dry-run removeu o arquivo e o digest do HOME
# voltou ao estado anterior. Agora tudo que escreve fica DEPOIS deste bloco.
if [ "$DRY" -eq 1 ]; then
  echo "== plano (nada sera escrito) =="
  LOCK_D="$DEST/evidence-gate/managed-files.lock"
  NOVO_D="$(awk -F"\t" '!/^#/{print $3}' "$MAN")"
  n=0
  while IFS=$'\t' read -r tipo origem destino digest; do
    case "$tipo" in ''|'#'*) continue;; esac
    if [ -e "$DEST/$destino" ]; then printf '  [dry] atualiza  %s\n' "$destino"
    else printf '  [dry] instala   %s\n' "$destino"; fi
    n=$((n+1))
  done < "$MAN"
  if [ -f "$LOCK_D" ]; then
    while IFS= read -r antigo; do
      [ -n "$antigo" ] || continue
      printf '%s\n' "$NOVO_D" | grep -qxF "$antigo" && continue
      [ -e "$DEST/$antigo" ] && printf '  [dry] REMOVERIA %s (saiu do manifesto)\n' "$antigo"
    done < "$LOCK_D"
  fi
  echo "  [dry] $n componentes; nenhuma escrita, remocao ou backup realizados."
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="$DEST/backups/apply-$TS"

if [ "$DRY" -eq 0 ]; then
  mkdir -p "$BK"
  for d in hooks agents skills; do [ -d "$DEST/$d" ] && cp -a "$DEST/$d" "$BK/" 2>/dev/null; done
  [ -f "$DEST/settings.json" ] && cp -a "$DEST/settings.json" "$BK/" 2>/dev/null
  echo "backup: $BK"
fi

N=0
while IFS=$'\t' read -r tipo origem destino digest; do
  case "$tipo" in ''|'#'*) continue;; esac
  alvo="$DEST/$destino"
  mkdir -p "$(dirname "$alvo")"
  if [ -d "$origem" ]; then rm -rf "$alvo"; cp -a "$origem" "$alvo"
  else cp -a "$origem" "$alvo"; case "$destino" in hooks/*|*/document-tools/*) chmod +x "$alvo";; esac; fi
  N=$((N+1))
done < "$MAN"
echo "componentes instalados: $N"

# CONVERGENCIA: apply(desired, installed) tem de resultar em installed == desired. Sem isto,
# componente removido do manifesto continuava instalado e ativo, e rodar apply de novo NAO
# resolvia o drift que o verify apontava. Remove apenas o que ESTE instalador gerenciou antes -
# nunca arquivo desconhecido em ~/.claude, que pode pertencer a outro sistema.
LOCK="$DEST/evidence-gate/managed-files.lock"
NOVO="$(awk -F"\t" '!/^#/{print $3}' "$MAN")"
if [ -f "$LOCK" ]; then
  while IFS= read -r antigo; do
    [ -n "$antigo" ] || continue
    printf '%s\n' "$NOVO" | grep -qxF "$antigo" && continue
    if [ -e "$DEST/$antigo" ]; then rm -rf "${DEST:?}/$antigo"; echo "  removido (saiu do manifesto): $antigo"; fi
  done < "$LOCK"
fi
mkdir -p "$(dirname "$LOCK")"; printf '%s\n' "$NOVO" > "$LOCK"

# --- registro de hooks no settings.json, preservando as demais chaves ---
S="$DEST/settings.json"; [ -f "$S" ] || echo '{}' > "$S"
# A lista de hooks NAO vive mais aqui. `install/hooks-spec.sh` e a fonte unica, consumida
# tambem por `install/apply-managed.sh`. Duas copias da mesma lista divergiriam em silencio -
# e o defeito central deste repositorio, e ele ja reincidiu como comentario obsoleto dentro de
# um hook. `$HOME` sai LITERAL: quem o expande e o runtime, na execucao.
HOOKS_JSON="$(bash "$(dirname "$0")/hooks-spec.sh" '$HOME/.claude/hooks')" || {
  echo "ERRO: nao foi possivel gerar a especificacao de hooks"; exit 1; }
TMPS="$(mktemp)"
if jq --argjson h "$HOOKS_JSON" \
      --arg ad "$DEST/evidence-gate/adapters/code" --arg dd "$DEST/evidence-gate/adapters/documents" \
      --arg rp "$REPO" \
      '.hooks=$h | .env=((.env//{}) + {CLAUDE_ADAPTERS_DIR:$ad, DOC_ADAPTERS_DIR:$dd, EVIDENCE_GATE_REPO:$rp})' \
      "$S" > "$TMPS" 2>/dev/null && jq -e . "$TMPS" >/dev/null 2>&1; then
  mv "$TMPS" "$S"; echo "settings.json: hooks registrados, demais chaves preservadas"
else
  rm -f "$TMPS"; echo "ERRO: nao foi possivel atualizar settings.json - nada foi alterado nele"; exit 1
fi

echo; echo "=== conformidade pos-instalacao ==="
bash install/verify.sh
