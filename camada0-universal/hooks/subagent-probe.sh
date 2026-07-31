#!/usr/bin/env bash
# INSTRUMENTACAO PERMANENTE - SubagentStart/SubagentStop.
# Registra o JSON bruto que o runtime entrega aos hooks de subagente, para MEDIR em vez de
# supor o que um subagente recebe. Nunca bloqueia: exit 0.
#
# Por que ficou permanente (ADR 0015): foi esta sonda que revelou que subagent-contract.sh lia
# o transcript da sessao PRINCIPAL em vez do subagente - defeito invisivel por leitura de
# codigo e por fixture sintetico. Sem instrumentacao do payload real, hook de subagente e
# escrito contra premissas nao verificadas. Regra adotada: hook novo so entra com um evento
# REAL capturado como fixture; esta sonda e quem os captura.
#
# PRIVACIDADE E TAMANHO: o payload inclui `last_assistant_message`, ou seja, o texto de saida
# do subagente. O log e local (~/.claude/logs), rotacionado ao passar de 2 MB, e nao sai da
# maquina. Para desligar: remova o hook do settings.json.
set -uo pipefail
IN="$(cat 2>/dev/null || true)"
LOG="${HOME}/.claude/logs/subagent-probe.jsonl"
{ mkdir -p "$(dirname "$LOG")" 2>/dev/null
  # rotacao simples: acima de 2 MB, mantem uma geracao anterior e recomeca.
  SZ=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  [ "$SZ" -gt 2097152 ] && mv -f "$LOG" "$LOG.1" 2>/dev/null
  printf '%s\n' "$IN" >> "$LOG"; } 2>/dev/null || true
exit 0
