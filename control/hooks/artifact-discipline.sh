#!/usr/bin/env bash
set -euo pipefail
if ! command -v jq >/dev/null 2>&1; then echo 'Bloqueado: artifact-discipline requer jq.' >&2; exit 2; fi
INPUT="$(cat)"
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || { echo 'Bloqueado: input JSON inválido.' >&2; exit 2; }
CONTENT="$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // empty),(.tool_input.new_string // empty),(.tool_input.edits[]?.new_string // empty),(.tool_input.new_source // empty)')"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
EMOJI='[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F000}-\x{1F2FF}\x{1F1E6}-\x{1F1FF}\x{FE0F}]'
printf '%s' "$CONTENT" | grep -P "$EMOJI" >/dev/null 2>&1 && { echo 'Bloqueado: emojis não permitidos.' >&2; exit 2; }
case "$FILE_PATH" in *.fable-allowed|*/verify-cmd-approved) echo 'Bloqueado: sentinela de autorização só pode ser criado pelo usuário.' >&2; exit 2;; */.claude/*) exit 0;; esac
LEXICO='seco seco|bora seco|voltagem maxima|voltagem máxima|modo overclock|lata velha|youtuber de extremo sucesso|programador de extremo sucesso|agente de extremo sucesso|otima observacao|ótima observação|excelente observacao|excelente observação|voce esta absolutamente certo|você está absolutamente certo|voce tem toda razao|você tem toda razão'
printf '%s' "$CONTENT" | grep -iE "$LEXICO" >/dev/null 2>&1 && { echo 'Bloqueado: léxico de hype/persona não deve vazar.' >&2; exit 2; }
exit 0
