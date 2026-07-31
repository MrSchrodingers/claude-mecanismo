#!/usr/bin/env bash
# Hook PreToolUse - GUARDA DURA DO MODELO FABLE. ADRs 0012, 0015 e 0016.
#
# Requisito: Fable NUNCA sem confirmacao EXPLICITA do usuario; subagente NUNCA, sem excecao.
# Isto e hook e nao regra escrita porque instrucao em CLAUDE.md tem adesao PROBABILISTICA.
#
# INVARIANTES:
#  1. Subagente (agent_id presente): negacao INCONDICIONAL. O sentinela nao e consultado.
#  2. O sentinela precisa pertencer a ROOT. `stat` SEM -L, deliberadamente: com -L, um symlink
#     para qualquer arquivo de root com inteiro grande (ex.: /proc/sys/kernel/shmmax) daria
#     auto-autorizacao. NAO trocar por `stat -L` nem `readlink -f`.
#  3. Guarda tambem os CAMINHOS DE CONSENTIMENTO (sentinela e verify-cmd-approved) contra
#     escrita por Bash - o artifact-discipline so cobre Write/Edit.
#  4. FAIL-CLOSED: sem jq ou input malformado com mencao a Fable -> nega.
# LIMITE: a deteccao em Bash e ancorada em posicao de comando e nao resiste a ofuscacao. A
# garantia esta no campo .model do Agent e no bloqueio por agent_id.
#
# PRE-CONDICAO DO AMBIENTE: agente != root e sudo com senha. Em CI/devcontainer como root, a
# garantia vale ZERO.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

# Deteccao ampla de proposito: cobre o campo model do Agent/Task, o texto de um script de
# Workflow, e a linha de comando de um Bash (--model fable, claude-fable-5, ANTHROPIC_MODEL=...).
# Este hook tambem guarda a lista de aprovacao do verify-cmd, pela mesma razao e com a
# mesma mecanica: caminho de CONSENTIMENTO que o modelo nao pode escrever. Roda antes do
# filtro de modelo porque nao tem relacao com selecao de modelo.
if [ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ]; then
  _C="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  if printf '%s' "$_C" | grep -qE 'verify-cmd-approved'; then
    if printf '%s' "$_C" | grep -qE '>[[:space:]]*[^|;&]*verify-cmd-approved|tee[^|;&]*verify-cmd-approved|(cp|mv|install|touch|truncate|dd|ln)[^|;&]*verify-cmd-approved|sed[^|;&]*-i[^|;&]*verify-cmd-approved'; then
      echo "Bloqueado: ~/.claude/verify-cmd-approved e a lista de comandos de projeto que o USUARIO autorizou. Escreve-la seria aprovar a si mesmo, e um repo hostil obteria execucao via prompt injection (classe do CVE-2025-59536). Mostre o comando ao usuario e peca que ELE aprove." >&2
      exit 2
    fi
  fi
fi

printf '%s' "$INPUT" | grep -qiE 'fable' || exit 0

# ===================== CAMADA 1: PROTECAO DO PROPRIO SENTINELA =====================
# DEFEITO ENCONTRADO E CORRIGIDO (ADR 0015): o artifact-discipline.sh so intercepta
# Write/Edit. Uma linha de Bash escrevendo o sentinela PASSAVA, e o modelo podia fabricar
# o proprio consentimento e usa-lo no turno seguinte - refutando a garantia anunciada no
# ADR 0012. Repro: {"tool_name":"Bash","tool_input":{"command":"echo ... > "$HOME"/.claude/.fable-allowed"}}
# retornava exit 0.
# Esta checagem roda ANTES do filtro de relevancia de modelo, porque escrever o sentinela nao
# e sintaxe de selecao de modelo e por isso escapava daquele filtro.
if [ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ]; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  if printf '%s' "$CMD" | grep -qE '\.fable-allowed'; then
    # Leitura pura (cat/ls/stat/test) e permitida: inspecionar o estado nao concede nada.
    if printf '%s' "$CMD" | grep -qE '>[[:space:]]*[^|;&]*\.fable-allowed|\.fable-allowed[^|;&]*<|tee[^|;&]*\.fable-allowed|(cp|mv|install|touch|truncate|dd|ln)[^|;&]*\.fable-allowed|sed[^|;&]*-i[^|;&]*\.fable-allowed|(chmod|chown)[^|;&]*\.fable-allowed'; then
      echo "Bloqueado (fable-guard): tentativa de ESCREVER o sentinela ~/.claude/.fable-allowed via Bash. O consentimento para o Fable e do USUARIO e nao pode ser produzido por voce - fabricar a propria autorizacao anula a confirmacao explicita. Peca ao usuario que rode o comando no shell dele." >&2
      exit 2
    fi
  fi
fi
# ==================================================================================

if ! command -v jq >/dev/null 2>&1; then
  echo "Bloqueado (fable-guard, fail-closed): mencao a Fable sem jq disponivel para inspecionar o contexto." >&2
  exit 2
fi

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)"

# Reduz falso positivo: so age se "fable" aparece onde de fato seleciona modelo, ou num
# comando de shell. Prosa que apenas MENCIONA a palavra nao e bloqueada.
RELEVANT=0
case "$TOOL" in
  Agent|Task)
    printf '%s' "$INPUT" | jq -er '.tool_input.model // empty' 2>/dev/null | grep -qi 'fable' && RELEVANT=1
    printf '%s' "$INPUT" | jq -er '.tool_input.subagent_type // empty' 2>/dev/null | grep -qi 'fable' && RELEVANT=1
    ;;
  Bash)
    # Ancorado em POSICAO DE COMANDO: so dispara quando `claude` esta no inicio da linha ou
    # depois de ; & | && ||, seguido de --model ...fable. Sem a ancora, o hook barrava
    # qualquer comando que apenas CONTIVESSE a string - inclusive o proprio script de teste
    # deste hook, um grep em documentacao, ou a escrita de um ADR que descreve a regra.
    # LIMITE reconhecido: uma linha ofuscada (base64, variavel indireta) escapa da ancora.
    # Isto e defesa em profundidade, nao a garantia. A garantia esta no caminho do Agent
    # (campo .model, comparacao exata) e no bloqueio incondicional em subagente por agent_id.
    printf '%s' "$INPUT" | jq -er '.tool_input.command // empty' 2>/dev/null \
      | grep -qiE '(^|[;&|][[:space:]]*)(env[[:space:]]+)?(ANTHROPIC_MODEL=["'"'"']?claude-fable|(npx[[:space:]]+)?claude([[:space:]]+[^;&|]*)?[[:space:]]--model[=[:space:]]+["'"'"']?(claude-)?fable)' && RELEVANT=1
    ;;
  Workflow)
    printf '%s' "$INPUT" | jq -er '(.tool_input.script // "") + " " + (.tool_input.name // "")' 2>/dev/null \
      | grep -qiE "model:[[:space:]]*['\"]?fable" && RELEVANT=1
    ;;
esac
[ "$RELEVANT" = "1" ] || exit 0

# Regra 1 - subagente: negacao incondicional.
if [ -n "$AGENT_ID" ]; then
  echo "Bloqueado (fable-guard): subagente NUNCA pode disparar com Fable. Esta negacao nao tem excecao e nao aceita o sentinela de autorizacao. Use o modelo herdado da sessao, ou opus/sonnet explicitamente." >&2
  exit 2
fi

# Regra 2 - sessao principal: exige sentinela valido.
# O sentinela precisa ser de ROOT (ADR 0015). Um arquivo que o usuario do agente consegue
# criar e, por definicao, um arquivo que o AGENTE consegue criar - eles sao o mesmo usuario.
# Bloquear as rotas de escrita conhecidas (Write/Edit e as formas de Bash) e defesa em
# profundidade, nao garantia: sempre restara uma forma nao prevista (ofuscacao, linguagem
# interpretada, utilitario incomum).
# Exigir posse por root move a barreira para fora do alcance do agente, porque `sudo` neste
# ambiente pede senha - algo que o modelo nao tem. E o unico ponto em que a "confirmacao
# EXPLICITA do usuario" deixa de ser convencao e passa a ser fato do sistema de arquivos.
# Custo: um `sudo` por janela de autorizacao. Aceitavel para um uso que deve ser raro e
# deliberado; se fosse frequente, o requisito de confirmacao explicita nao faria sentido.
SENT="${HOME}/.claude/.fable-allowed"
NOW="$(date +%s 2>/dev/null || echo 0)"
if [ -f "$SENT" ]; then
  # `stat` SEM -L, deliberadamente: reporta o dono do SYMLINK, nao do alvo.
  # Se seguisse o link, bastaria ao agente apontar o sentinela para qualquer arquivo de root
  # cujo conteudo seja um inteiro grande (ex.: /proc/sys/kernel/shmmax = 18446744073692774399,
  # dono root, muito maior que o epoch atual) para se autorizar. Este ataque foi TENTADO
  # durante o teste do ramo de aceite e o guarda o bloqueou porque o symlink pertence ao
  # usuario, nao a root. Nao troque por `stat -L` nem por `readlink -f`.
  OWNER="$(stat -c '%U' "$SENT" 2>/dev/null || echo '?')"
  EXP="$(sed -n '1p' "$SENT" 2>/dev/null | tr -cd '0-9')"
  if [ "$OWNER" != "root" ]; then
    echo "Bloqueado (fable-guard): o sentinela ~/.claude/.fable-allowed existe mas pertence a '$OWNER', nao a root. Um arquivo que voce mesmo poderia criar nao serve como consentimento do usuario. Peca ao usuario: sudo sh -c 'echo \$(( \$(date +%s) + 3600 )) > "$HOME"/.claude/.fable-allowed'" >&2
    exit 2
  fi
  if [ -n "$EXP" ] && [ "$NOW" -gt 0 ] && [ "$EXP" -gt "$NOW" ]; then
    echo "fable-guard: uso de Fable AUTORIZADO pelo usuario (sentinela de root) ate $(date -d "@$EXP" 2>/dev/null || echo "epoch $EXP")." >&2
    exit 0
  fi
fi

cat >&2 <<'MSG'
Bloqueado (fable-guard): Fable exige confirmacao EXPLICITA do usuario e nao ha autorizacao ativa.

Voce NAO consegue criar a autorizacao: o sentinela precisa pertencer a root, e obte-lo exige
`sudo` com senha - que voce nao tem. Isto e deliberado; se voce pudesse cria-lo, a
"confirmacao explicita" seria voce autorizando a si mesmo.

Peca ao USUARIO que rode, no shell dele (ou com o prefixo `!` na sessao):

    sudo sh -c 'echo $(( $(date +%s) + 3600 )) > "$HOME"/.claude/.fable-allowed'   # libera por 1h

Enquanto isso, prossiga com o modelo herdado da sessao (opus/sonnet). Nao tente rotas
alternativas para alcancar o Fable - isso e contorno de politica, nao solucao.
MSG
exit 2
