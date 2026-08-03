#!/usr/bin/env bash
# PLANO DE CONTROLE - conformidade no inicio da sessao.  Hook: SessionStart.
#
# Existe porque o defeito mais grave encontrado neste projeto nao foi um bug de logica: foi a
# divergencia silenciosa entre o repositorio e a maquina. 32 componentes ativos, 12 versionados,
# um verify-gate uma versao atras - por meses, sem nenhum sinal. Nao havia quem comparasse.
#
# Este hook e o comparador. Ele nao corrige e nao bloqueia: declara, no primeiro turno, que o
# que esta rodando diverge do que o repositorio afirma. Bloquear a sessao por drift seria o
# falso positivo que faz o operador desligar o mecanismo.
#
# LIMITE DECLARADO: este hook vive em ~/.claude/hooks, que o ator governado pode escrever.
# Ele detecta drift acidental, nao adversario. Contra ator com intencao, a raiz de confianca
# precisa ser managed settings + launcher nao gravavel (docs/adr/0022, fase 2).
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
cat >/dev/null 2>&1 || true   # drena stdin

REPO="${EVIDENCE_GATE_REPO:-$HOME/claude-mecanismo}"
[ -d "$REPO" ] || REPO="$HOME/evidence-gate"
[ -x "$REPO/install/verify.sh" ] || exit 0

OUT="$(cd "$REPO" && bash install/verify.sh 2>&1)"; RC=$?

# HEARTBEAT: silencio nao prova conformidade - prova apenas ausencia de mensagem. Este hook sai
# 0 calado em pelo menos seis cenarios (jq ausente, repo nao localizado, verify nao executavel,
# hook nao carregado, SessionStart removido, hook apagado). Sem registro observavel, "nao vi
# nada" e indistinguivel de "o mecanismo esta morto". O log e a prova de liveness; a ausencia
# de mensagem ao modelo e so higiene de contexto.
HB="$HOME/.claude/evidence/session-integrity.jsonl"
mkdir -p "$(dirname "$HB")" 2>/dev/null || true
MANDIG="$(sha256sum "$REPO/install/manifest.lock" 2>/dev/null | cut -c1-16)"
jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
       --arg r "$([ "$RC" -eq 0 ] && echo conformant || echo drift)" \
       --arg m "${MANDIG:-unknown}" --arg s "$(printf '%s' "$OUT" | grep -E '^conformidade:' | head -1)" \
       '{ts:$t,event:"session_integrity",result:$r,manifest_digest:$m,summary:$s,policy:"user"}' \
  >> "$HB" 2>/dev/null || true

[ "$RC" -eq 0 ] && exit 0

RESUMO="$(printf '%s' "$OUT" | grep -E '^conformidade:' | head -1)"
DETALHE="$(printf '%s' "$OUT" | grep -E '^  (DIVERGE|AUSENTE|ORFAO)' | head -12)"

jq -cn --arg c "CONFORMIDADE - o que roda diverge do que o repositorio declara.

$RESUMO
$DETALHE

O estado instalado NAO e o estado versionado. Qualquer afirmacao sobre o comportamento do
harness baseada no repositorio esta, neste turno, sem referente verificado.
Para reconciliar: cd $REPO && bash install/apply.sh
Para inspecionar: cd $REPO && bash install/verify.sh" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null
exit 0
