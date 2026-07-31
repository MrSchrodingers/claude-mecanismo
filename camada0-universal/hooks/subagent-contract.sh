#!/usr/bin/env bash
# Hook SubagentStop - VALIDA O CONTRATO DE RETORNO do subagente. ADRs 0011, 0014 e 0018.
#
# INVARIANTES:
#  1. A fonte e `last_assistant_message`, com fallback `agent_transcript_path`. NUNCA
#     `transcript_path` - esse e o transcript do PAI, e usa-lo produzia veredito sobre a prosa
#     do orquestrador: falso positivo E falso negativo ao mesmo tempo. Ver ADR 0014.
#  2. O texto e NORMALIZADO antes de casar: os agentes escrevem em PT-BR e emitem EVIDENCIA
#     acentuada. Casar so o ASCII reprovava 25% dos retornos reais. Ver ADR 0018.
#  3. A filtragem por tipo de agente e feita AQUI, nao so pelo matcher: a maioria dos eventos
#     SubagentStop vem com agent_type vazio e e outra classe de evento.
# Anti-loop: respeita stop_hook_active. FAIL-OPEN.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

AT="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
case "$AT" in
  investigador|mapeador-dependencias|revisor-codigo|refutador|auditor-seguranca|\
  analista-otimalidade|analista-fluxos|revisor-frontend|implementador|tdd) ;;
  # implementador e tdd ENTRAM (4a arguicao, achado 8): o CLAUDE.md anuncia o contrato como
  # universal e eles ficavam de fora - o agente que ESCREVE CODIGO era o unico nao cobrado
  # por evidencia. Exige o matcher correspondente no settings.json e no hooks.json.
  # implementador|tdd foram REMOVIDOS: constavam aqui mas nao no matcher do settings.json,
  # entao o ramo era inalcancavel em producao. Deadcode achado na 2a arguicao.
  *) exit 0 ;;   # tipo vazio ou de terceiro: nao e nosso contrato, nao opinar.
esac

# 1. campo dedicado com o texto final completo.
LAST="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"

# 2. fallback: transcript DO SUBAGENTE (nunca o do pai).
if [ -z "$LAST" ]; then
  AP="$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)"
  if [ -n "$AP" ] && [ -f "$AP" ]; then
    LAST="$(tail -n 80 "$AP" 2>/dev/null | jq -r '
      select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | tail -n 200)"
  fi
fi
[ -n "$LAST" ] || exit 0   # sem fonte confiavel: calar, nunca chutar.

# ===================== NORMALIZACAO DE ACENTO (ADR 0018) =====================
# DEFEITO GRAVE CORRIGIDO: o padrao era ASCII (`EVIDENCIA`), mas o CLAUDE.md manda os agentes
# raciocinarem em PT-BR e eles emitem `EVIDENCIA` COM acento. Medido sobre os eventos reais do
# log da sonda: 4 de 16 retornos nomeados (25%) foram REPROVADOS so por isso - entre eles uma
# revisao de 36.188 bytes com os quatro blocos presentes. O mecanismo criado para punir
# afirmacao sem lastro estava acusando de falta de lastro justamente quem o forneceu.
#
# O defeito e ANTERIOR a correcao da fonte do transcript (ADR 0014); era mascarado por ela.
# Ler o arquivo errado dava 0 blocos sempre, entao o acento nunca chegava a importar.
# Corrigir a fonte ATIVOU este.
#
# A correcao NAO e adicionar a variante acentuada de uma palavra - isso repetiria o erro na
# proxima (PROPAGACAO, RISCOS...). Normaliza-se o texto ANTES de casar, e todos os padroes
# passam a ser ASCII por construcao.
NORM="$(printf '%s' "$LAST" | sed 'y/ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ/AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn/')"
# =============================================================================

MISS=""
grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*RESULTADO' <<<"$NORM" || MISS="$MISS RESULTADO"

if grep -qiE '^[[:space:]]*[-*#]*[[:space:]]*EVIDENCIA' <<<"$NORM"; then
  grep -qE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+|exit[[:space:]]*(code)?[[:space:]]*[=:]?[[:space:]]*[0-9]|\$ |^[[:space:]]*(git|npm|pytest|ruff|mypy|eslint|pip-audit|npx|go|cargo|jq|grep|rg|sed|awk|tail) ' <<<"$NORM" \
    || MISS="$MISS ANCORA-DE-EVIDENCIA"
else
  MISS="$MISS EVIDENCIA"
fi

[ -n "$MISS" ] || exit 0

{
  echo "CONTRATO DE RETORNO INCOMPLETO (agente: $AT). Faltou:$MISS"
  echo "Feche com os quatro blocos, nesta ordem:"
  echo "  RESULTADO   - o que foi feito ou encontrado."
  echo "  EVIDENCIA   - arquivo:linha, comando executado e sua saida. Sem ancora verificavel,"
  echo "                a conclusao e auto-avaliacao, e auto-avaliacao nao e sinal."
  echo "  RISCOS      - o que ficou em aberto ou precisa de decisao."
  echo "  PROPAGACAO  - pontos do grafo de dependencias afetados (ou 'nenhum', justificado)."
  echo "Se nao conseguiu obter evidencia, diga isso em EVIDENCIA - 'nao verificado' e resposta"
  echo "valida; afirmacao sem lastro nao e."
} >&2
exit 2
