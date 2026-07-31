#!/usr/bin/env bash
# Hook PreToolUse (Write|Edit|MultiEdit) - AUDITORIA DE AUTO-MODIFICACAO (ADR 0019).
#
# Modo de falha nº3 da RFC anthropics/claude-code#45427, CONFIRMADO neste ambiente:
#   `[ -w ~/.claude/hooks/fable-guard.sh ]` -> verdadeiro
#   `[ -w ~/.claude/settings.json ]`        -> verdadeiro
# O modelo tem permissao de escrita sobre as proprias guardas e sobre a fiacao delas. Pode,
# portanto, desligar qualquer garantia desta config. O autor da RFC observou 3 incidentes
# reais de auto-modificacao em 12 meses de uso (2 detectados).
#
# ESTE HOOK NAO PREVINE - ELE DETECTA E REGISTRA. A distincao e o ponto:
#  - PREVENIR exigiria bloquear toda escrita em hooks/ e settings.json, o que tornaria a
#    manutencao da propria config impossivel sem desligar o hook - e um mecanismo que se
#    desliga para trabalhar nao e mecanismo.
#  - A RFC pede a solucao correta (um tool gate DENTRO do CLI, com `protected: true`, fora do
#    alcance do modelo). Ela foi FECHADA COMO NOT PLANNED. Nao existe primitiva para isso.
# Logo: o melhor disponivel e trilha de auditoria duravel + aviso de alta saliencia. Assumir
# que isso e "protecao" seria o falso rigor que esta config condena. E deteccao.
#
# O que o usuario ganha: `cat ~/.claude/logs/self-mod-audit.log` mostra toda alteracao de
# guarda, com data, arquivo e sessao. Um desligamento silencioso deixa de ser silencioso.
# FAIL-OPEN: nunca bloqueia (exit 0 sempre).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
F="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$F" ] || exit 0

case "$F" in
  */.claude/hooks/*|*/.claude/settings.json|*/.claude/settings.local.json|\
  */claude-colegio-analitico/hooks/*|*/claude-colegio-analitico/settings.json) ;;
  *) exit 0 ;;
esac

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "?"' 2>/dev/null | cut -c1-8)"
AID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null | cut -c1-8)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null)"
LOG="${HOME}/.claude/logs/self-mod-audit.log"
{ mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s\t%s\t%s\tsession=%s%s\n' "$(date -u +%FT%TZ 2>/dev/null)" "$TOOL" "$F" "$SID" \
    "${AID:+ subagente=$AID}" >> "$LOG"; } 2>/dev/null || true

MSGF="$(mktemp 2>/dev/null)" || exit 0
{
  echo "[AUDITORIA DE AUTO-MODIFICACAO] $TOOL em $F"
  echo "Voce esta alterando um mecanismo de enforcement ou a fiacao dele. Registrado em"
  echo "~/.claude/logs/self-mod-audit.log - a alteracao nao e silenciosa."
  echo "Se a mudanca ENFRAQUECE uma guarda (remove checagem, alarga excecao, troca exit 2 por"
  echo "exit 0, desliga hook no settings.json), diga isso ao usuario EXPLICITAMENTE na resposta,"
  echo "com o antes e o depois. Enfraquecer guarda em silencio e o modo de falha que esta"
  echo "trilha existe para tornar visivel."
} > "$MSGF"

# CANAL (ADR 0021): stderr com exit 0 NAO chega ao modelo - fica so no `hook_success`,
# cujo `content` vem VAZIO. Medido por A/B com controle positivo e confirmado no
# trafego real. Aviso que precisa ser LIDO usa additionalContext; exit 2 fica para
# quem precisa BLOQUEAR. Nao voltar para `>&2`: o hook vira decoracao silenciosa.
jq -n --rawfile c "$MSGF" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
rm -f "$MSGF" 2>/dev/null
exit 0
