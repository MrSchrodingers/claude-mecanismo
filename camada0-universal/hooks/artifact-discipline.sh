#!/usr/bin/env bash
# Disciplina de artefato para Write/Edit/MultiEdit/NotebookEdit. Recebe JSON via stdin.
# Exit 2 = bloqueia a operacao e devolve a mensagem ao Claude via stderr.
#
# Regra 1 (sempre): emojis nao sao permitidos em nenhum artefato.
# Regra 2 (artefatos NAO-meta): lexico de hype/persona e de bajulacao nao deve vazar
#   para codigo, docs e mensagens. Arquivos sob um diretorio .claude/ (config meta que
#   DOCUMENTA esse lexico: CLAUDE.md, agents/, hooks/, docs/adr/, memory/) sao isentos
#   da Regra 2 de proposito. ADR/agents/hooks de PROJETO fora de .claude/ NAO sao isentos.
set -euo pipefail

# Fail-closed: sem jq nao da para inspecionar o artefato. Bloquear e mais seguro do que
# liberar cego (fail-open silencioso desativaria o guard sem aviso).
if ! command -v jq >/dev/null 2>&1; then
  echo "Bloqueado: artifact-discipline requer jq para inspecionar o conteudo, e jq nao esta no PATH. Instale jq (ou ajuste o hook)." >&2
  exit 2
fi

INPUT="$(cat)"

# Fail-closed tambem para input malformado: se nao for JSON valido, bloquear (coerente com
# a postura fail-closed do header; nao confundir input invalido com conteudo vazio legitimo).
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "Bloqueado: artifact-discipline recebeu input que nao e JSON valido (fail-closed)." >&2
  exit 2
fi

# Campos de conteudo por ferramenta: Write=content, Edit=new_string,
# MultiEdit=edits[].new_string, NotebookEdit=new_source.
CONTENT="$(printf '%s' "$INPUT" | jq -r '
  (.tool_input.content // empty),
  (.tool_input.new_string // empty),
  (.tool_input.edits[]?.new_string // empty),
  (.tool_input.new_source // empty)
' 2>/dev/null || true)"

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

# Regra 1 - emojis em qualquer artefato. Faixas cobrem pictogramas, simbolos/dingbats,
# setas-estrelas suplementares, simbolos diversos, bandeiras e o seletor de variacao.
# Nota: a faixa 2600-27BF e deliberadamente estrita e tambem barra dingbats tecnicos
# (check U+2713, ballot-x U+2717, warning U+26A0). Intencional (politica no-emoji); em
# doc/checklist use ASCII ([x], OK, WARN, ->) em vez desses glifos. Vale ate sob .claude/.
EMOJI='[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F000}-\x{1F2FF}\x{1F1E6}-\x{1F1FF}\x{FE0F}]'
if printf '%s' "$CONTENT" | grep -P "$EMOJI" >/dev/null 2>&1; then
  echo "Bloqueado: emojis nao sao permitidos (diretriz global). Remova-os e tente de novo." >&2
  exit 2
fi

# Regra 0 (precede tudo, inclusive a isencao .claude/) - SENTINELA DE AUTORIZACAO DO FABLE.
# ~/.claude/.fable-allowed e o consentimento EXPLICITO do usuario para uso do modelo Fable,
# lido por fable-guard.sh. Se o modelo pudesse escrever esse arquivo, ele fabricaria o proprio
# consentimento e a "confirmacao explicita" viraria teatro. Este bloqueio e o que torna a
# garantia real: o sentinela so pode nascer do shell do usuario.
case "$FILE_PATH" in
  *.fable-allowed)
    echo "Bloqueado: o sentinela do Fable e o consentimento explicito do USUARIO e nao pode ser escrito por voce - seria fabricar a propria autorizacao. Ele tambem precisa pertencer a root; peca ao usuario que o crie com sudo." >&2
    exit 2 ;;
  */verify-cmd-approved)
    echo "Bloqueado: ~/.claude/verify-cmd-approved e a lista de comandos de projeto que o USUARIO autorizou a executar. Se voce pudesse escrever nela, um repositorio hostil obteria execucao de comando via prompt injection - a classe do CVE-2025-59536. So o usuario aprova, depois de ler o comando." >&2
    exit 2 ;;
esac

# Isencao da Regra 2: qualquer artefato sob um diretorio .claude/ (config meta que
# documenta o proprio lexico). Codigo de projeto em src/agents/, docs/adr/, hooks/ etc.
# fora de .claude/ continua sujeito a Regra 2.
case "$FILE_PATH" in
  */.claude/*)
    exit 0 ;;
esac

# Regra 2 - hype/persona ou bajulacao INEQUIVOCA vazando para artefato comum. Lista
# enxuta de proposito: so expressoes que nao aparecem em codigo/doc legitimo. A
# disciplina anti-bajulacao plena (chat) vive no CLAUDE.md secao 3, nao neste hook.
# Esta guarda e DELIBERADAMENTE estreita (so bajulacao lexical explicita): a bajulacao
# substantiva - concordar com premissa falsa, abandonar resposta correta sob pressao - e
# indetectavel por regex (concordancia inter-avaliador humana baixa entre especialistas; ADR 0002).
# Captura-la e papel do prompt (CLAUDE.md secao 3) e dos agentes cetico/revisor-critico.
# A persona vigente e o Colegio Analitico (CLAUDE.md Parte I.2); bordoes antigos de persona
# permanecem na lista como guarda defensiva contra regressao.
# Ao adicionar termo, inclua variante com e sem acento (grep -iE nao e diacritic-insensitive).
LEXICO='seco seco|bora seco|voltagem maxima|voltagem máxima|modo overclock|lata velha|youtuber de extremo sucesso|programador de extremo sucesso|agente de extremo sucesso|otima observacao|ótima observação|excelente observacao|excelente observação|voce esta absolutamente certo|você está absolutamente certo|voce tem toda razao|você tem toda razão'

if printf '%s' "$CONTENT" | grep -iE "$LEXICO" >/dev/null 2>&1; then
  echo "Bloqueado: lexico de hype/persona ou de bajulacao nao deve vazar para artefato. Artefato e neutro (diretriz global, secao 1). Reescreva sem essas expressoes." >&2
  exit 2
fi

exit 0
