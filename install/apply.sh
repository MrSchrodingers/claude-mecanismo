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
  if [ "$DRY" -eq 1 ]; then printf '  [dry] %s -> %s\n' "$origem" "$destino"; N=$((N+1)); continue; fi
  mkdir -p "$(dirname "$alvo")"
  if [ -d "$origem" ]; then rm -rf "$alvo"; cp -a "$origem" "$alvo"
  else cp -a "$origem" "$alvo"; [ "${destino%%/*}" = "hooks" ] && chmod +x "$alvo"; fi
  N=$((N+1))
done < "$MAN"
echo "componentes instalados: $N"
[ "$DRY" -eq 1 ] && exit 0

# --- registro de hooks no settings.json, preservando as demais chaves ---
S="$DEST/settings.json"; [ -f "$S" ] || echo '{}' > "$S"
HOOKS_JSON="$(cat <<'JSON'
{
  "SessionStart": [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/session-integrity.sh","timeout":15}]}],
  "PreToolUse": [
    {"matcher":"Write|Edit|MultiEdit|NotebookEdit","hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/artifact-discipline.sh"},
      {"type":"command","command":"bash $HOME/.claude/hooks/self-mod-audit.sh","timeout":5}]},
    {"matcher":"Agent|Task|Bash|Workflow","hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/fable-guard.sh","timeout":5}]},
    {"matcher":"Read","hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/read-budget.sh","timeout":10}]}
  ],
  "UserPromptSubmit": [{"hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/lentes.sh","timeout":5},
      {"type":"command","command":"bash $HOME/.claude/hooks/ds4-notify.sh","timeout":5},
      {"type":"command","command":"bash $HOME/.claude/hooks/graphify-scout-mode.sh","timeout":5}]}],
  "PostToolUse": [
    {"matcher":"Write|Edit|MultiEdit|NotebookEdit","hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/poka-yoke-lint.sh"},
      {"type":"command","command":"bash $HOME/.claude/hooks/risk-trigger.sh"}]},
    {"matcher":"Bash","hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/output-budget.sh"}]}
  ],
  "Stop": [{"hooks":[
      {"type":"command","command":"bash $HOME/.claude/hooks/verify-gate.sh","timeout":200},
      {"type":"command","command":"bash $HOME/.claude/hooks/ds4-notify.sh","timeout":5}]}],
  "SubagentStop": [
    {"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/subagent-probe.sh"}]},
    {"matcher":"investigador|mapeador-dependencias|revisor-codigo|refutador|auditor-seguranca|analista-otimalidade|analista-fluxos|revisor-frontend|implementador|tdd",
     "hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/subagent-contract.sh"}]},
    {"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/ds4-notify.sh","timeout":5}]}
  ],
  "SubagentStart": [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/subagent-probe.sh"}]}],
  "Notification": [{"hooks":[{"type":"command","command":"bash $HOME/.claude/hooks/ds4-notify.sh","timeout":5}]}]
}
JSON
)"
TMPS="$(mktemp)"
if jq --argjson h "$HOOKS_JSON" \
      --arg ad "$DEST/evidence-gate/adapters/code" \
      --arg rp "$REPO" \
      '.hooks=$h | .env=((.env//{}) + {CLAUDE_ADAPTERS_DIR:$ad, EVIDENCE_GATE_REPO:$rp})' \
      "$S" > "$TMPS" 2>/dev/null && jq -e . "$TMPS" >/dev/null 2>&1; then
  mv "$TMPS" "$S"; echo "settings.json: hooks registrados, demais chaves preservadas"
else
  rm -f "$TMPS"; echo "ERRO: nao foi possivel atualizar settings.json - nada foi alterado nele"; exit 1
fi

echo; echo "=== conformidade pos-instalacao ==="
bash install/verify.sh
