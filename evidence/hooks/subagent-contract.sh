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
#
# SEGUNDA CORRECAO (2026-08-03): `y/.../.../` opera sobre CARACTERES, e sob LC_ALL=C o sed
# processa BYTES - a transliteracao multi-byte quebra e o texto sai intacto. Resultado: o hook
# voltava a reprovar retorno acentuado, agora dependendo do locale do ambiente. Reproduzido:
# `LC_ALL=C bash tests/unit/run.sh` reprovava 2 casos que passavam sem a variavel.
# Substituicao LITERAL por byte e insensivel a locale: cada `s///` casa uma sequencia fixa.
NORM="$(printf '%s' "$LAST" | sed \
  -e 's/Á/A/g' -e 's/À/A/g' -e 's/Â/A/g' -e 's/Ã/A/g' -e 's/Ä/A/g' \
  -e 's/É/E/g' -e 's/È/E/g' -e 's/Ê/E/g' -e 's/Ë/E/g' \
  -e 's/Í/I/g' -e 's/Ì/I/g' -e 's/Î/I/g' -e 's/Ï/I/g' \
  -e 's/Ó/O/g' -e 's/Ò/O/g' -e 's/Ô/O/g' -e 's/Õ/O/g' -e 's/Ö/O/g' \
  -e 's/Ú/U/g' -e 's/Ù/U/g' -e 's/Û/U/g' -e 's/Ü/U/g' -e 's/Ç/C/g' -e 's/Ñ/N/g' \
  -e 's/á/a/g' -e 's/à/a/g' -e 's/â/a/g' -e 's/ã/a/g' -e 's/ä/a/g' \
  -e 's/é/e/g' -e 's/è/e/g' -e 's/ê/e/g' -e 's/ë/e/g' \
  -e 's/í/i/g' -e 's/ì/i/g' -e 's/î/i/g' -e 's/ï/i/g' \
  -e 's/ó/o/g' -e 's/ò/o/g' -e 's/ô/o/g' -e 's/õ/o/g' -e 's/ö/o/g' \
  -e 's/ú/u/g' -e 's/ù/u/g' -e 's/û/u/g' -e 's/ü/u/g' -e 's/ç/c/g' -e 's/ñ/n/g')"
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
