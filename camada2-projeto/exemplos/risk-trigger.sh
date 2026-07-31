#!/usr/bin/env bash
# Hook PostToolUse (Write|Edit|MultiEdit) - GATILHO DETERMINISTICO DE REVISAO.
#
# Substitui frontend-review-reminder.sh e generaliza o mecanismo (ADR 0011). O gating do
# pipeline era 100% disciplina: a sessao classificava o diff de cabeca e decidia quais
# agentes acionar. Classificacao por memoria falha sob carga - e o modo de falha e sempre
# no sentido de SUBclassificar (o A01/IDOR cabe numa linha que parece refactor trivial).
# Este hook decide pela SUPERFICIE TOCADA, lida do conteudo real, nao da percepcao.
#
# Detecta por (a) extensao do arquivo e (b) PADRAO no conteudo escrito, e devolve ao modelo
# quais lentes o diff acabou de disparar. LIMITE honesto: o hook ENTREGA o gatilho de forma
# deterministica; nenhum hook forca o spawn do subagente. Ele torna a omissao impossivel de
# ser silenciosa, nao impossivel.
#
# Throttle por categoria (~10 min) para nao repetir a cada arquivo de uma sequencia de edicoes.
# FAIL-OPEN: sem jq, sem file_path, ou nada detectado -> exit 0. Nunca bloqueia a escrita.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
F="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || true)"
[ -n "$F" ] || exit 0

C="$(printf '%s' "$INPUT" | jq -r '
  (.tool_input.content // empty),
  (.tool_input.new_string // empty),
  (.tool_input.edits[]?.new_string // empty)' 2>/dev/null || true)"
[ -n "$C" ] || exit 0

HITS=""
add() { case " $HITS " in *" $1 "*) ;; *) HITS="$HITS $1";; esac; }

# --- (a) superficie por extensao ---
case "$F" in
  *.vue|*.tsx|*.jsx|*.svelte|*.astro|*.html|*.css|*.scss|*.sass|*.less|*.styl) add UI ;;
esac
case "$(basename "$F")" in
  package.json|package-lock.json|pnpm-lock.yaml|yarn.lock|requirements.txt|pyproject.toml|\
  poetry.lock|Pipfile.lock|go.mod|go.sum|Cargo.toml|Cargo.lock|Gemfile.lock|composer.lock) add DEP ;;
esac

# --- (b) superficie por conteudo ---
# Acesso a dado / autorizacao / entrada nao-confiavel: a familia A01 (broken access control),
# que e a vuln mais comum e a que mais se disfarca de CRUD rotineiro.
grep -qiE '\.(objects|query|filter|exclude|get_queryset|raw)\(|\bSELECT .*\bFROM\b|\bUPDATE .+\bSET\b|\bDELETE FROM\b|findOne|findMany|createQueryBuilder|knex\(' <<<"$C" && add DATA
grep -qiE 'request\.(user|GET|POST|data|body|query|params|headers)|req\.(body|query|params|headers|cookies)|is_authenticated|permission_classes|@login_required|has_perm|current_user|session\[' <<<"$C" && add AUTHZ
grep -qiE 'os\.system|subprocess|shell=True|eval\(|exec\(|pickle\.loads|yaml\.load\(|innerHTML|dangerouslySetInnerHTML|new Function\(|child_process' <<<"$C" && add EXEC
grep -qiE '(secret|token|api[_-]?key|password|passwd|private[_-]?key|credential)[[:space:]]*[:=][[:space:]]*.[A-Za-z0-9_/+-]{12,}' <<<"$C" && add SECRET
# Custo assintotico: laco ANINHADO (deteccao por indentacao crescente, nao por regex com \n -
# ERE nao conhece \n e `grep -E` emitia "stray \ before n" no stderr a cada escrita, poluindo
# o contexto do modelo com warning em todo Write/Edit), ou busca linear dentro de laco.
awk '
  match($0, /(^|[^[:alnum:]_])(for|while)([^[:alnum:]_]|$)/) {
    ind = match($0, /[^ \t]/) - 1
    if (open && ind > base) { found = 1; exit }
    open = 1; base = ind; next
  }
  END { exit(found ? 0 : 1) }
' <<<"$C" && add ALGO
grep -qiE '\.filter\(.*\.filter\(|\.index\(|O\(n\^?2\)' <<<"$C" && add ALGO

[ -n "$HITS" ] || exit 0

# Throttle por assinatura de categorias.
SIG="$(printf '%s' "$HITS" | tr -d ' ' | md5sum 2>/dev/null | cut -c1-10 || echo x)"
STAMP="${HOME}/.claude/logs/.risktrig-${SIG}"
NOW="$(date +%s 2>/dev/null || echo 0)"; LAST=0; [ -f "$STAMP" ] && LAST="$(sed -n '1p' "$STAMP" 2>/dev/null || echo 0)"
case "${NOW}x${LAST}" in *[!0-9x]*) NOW=0; LAST=0;; esac
[ "$NOW" -gt 0 ] && [ "$((NOW-LAST))" -lt 600 ] && exit 0
{ mkdir -p "$(dirname "$STAMP")" 2>/dev/null && printf '%s' "$NOW" > "$STAMP"; } 2>/dev/null || true

MSGF="$(mktemp 2>/dev/null)" || exit 0
{
echo "[GATILHO DE REVISAO] $F tocou superficie de risco:$HITS"
case " $HITS " in *" DATA "*|*" AUTHZ "*)
  echo "- DADO/AUTORIZACAO -> este diff e NAO TRIVIAL por definicao, qualquer que seja o tamanho."
  echo "  revisor-codigo e obrigatorio. Verifique escopo-do-dono (o filtro por owner/tenant"
  echo "  continua na query?), mass-assignment, e injecao via filtro/order_by vindo do request." ;;
esac
case " $HITS " in *" EXEC "*)
  # DESDUPLICADO (ADR 0019): o plugin security-guidance cobre 100% dos tokens desta categoria
  # (os.system, subprocess, eval, pickle, yaml.load, innerHTML, dangerouslySetInnerHTML,
  # new Function, child_process) com 25 regras nativas e remediacao mais especifica que a que
  # eu escreveria. A EXPLICACAO da vuln e dele. Aqui fica so o ROTEAMENTO, que ele nao faz.
  # RAZAO DE NAO REMOVER DE VEZ: o aviso do plugin DECAI - ele avisa N vezes por regra por
  # sessao e depois silencia (anti-fadiga, ~/.claude/security_warnings_state_<id>.json).
  # O roteamento nao pode decair: numa sessao longa, o ultimo diff arriscado precisa acionar
  # o agente tanto quanto o primeiro.
  echo "- EXECUCAO/DESERIALIZACAO/SINK-DOM -> acione auditor-seguranca (gated), que RODA scanner."
  # A sobreposicao com o plugin e 9 de 11, nao 100% como o ADR 0019 afirmava (medido na 4a
  # arguicao). Duas lacunas REAIS, que precisam da explicacao aqui porque o plugin cala:
  case "$C" in *"exec("*)
    echo "  ATENCAO: exec() em Python NAO e coberto pelo plugin (a regra nativa eval_injection"
    echo "  usa lookbehind que nao casa exec). exec() compila e roda a string: com entrada do"
    echo "  usuario e execucao arbitraria. Use um dispatch explicito, nunca exec/eval." ;;
  esac
  case "$C" in *"child_process"*)
    echo "  ATENCAO: child_process na forma require NAO e coberto pelo plugin (a regra nativa"
    echo "  exige a forma .exec( com path_filter de JS). Prefira execFile com array de"
    echo "  argumentos; exec() com string monta shell e e sink de injecao." ;;
  esac
  echo "  As demais classes (os.system, eval, pickle, yaml.load, innerHTML, new Function) tem"
  echo "  explicacao propria do plugin security-guidance; nao a repita." ;;
esac
case " $HITS " in *" SECRET "*)
  echo "- POSSIVEL SEGREDO LITERAL -> confirme se e placeholder. Se for real: rotacione, mova para"
  echo "  variavel de ambiente, e verifique se ja entrou no historico do git." ;;
esac
case " $HITS " in *" DEP "*)
  echo "- MANIFESTO/LOCKFILE -> auditor-seguranca (gated): pip-audit / npm audit --omit=dev."
  echo "  Priorize por exploracao conhecida (CISA KEV, EPSS), nao so por CVSS." ;;
esac
case " $HITS " in *" UI "*)
  echo "- UI -> revisor-frontend (agente) antes de declarar pronto. WCAG 2.2 e portao"
  echo "  BINARIO (contraste 4.5:1 texto normal, 3:1 grande/nao-texto, alvo 24x24, foco visivel)."
  echo "  Checker automatico e necessario e INSUFICIENTE: 541 violacoes semanticas passaram em"
  echo "  checagem automatica em 300 UIs geradas por LLM (Calo et al., CHI EA 2026,"
  echo "  DOI 10.1145/3772363.3799364) - alt=\"image\", link \"clique aqui\"."
  echo "  Leia o texto alternativo e o rotulo, nao so o atributo." ;;
esac
case " $HITS " in *" ALGO "*)
  echo "- LACO ANINHADO / BUSCA LINEAR EM LACO -> analista-otimalidade se o custo de reversao for"
  echo "  alto. Compare o custo assintotico com o LIMITE INFERIOR do problema, nao com a versao"
  echo "  anterior; e meca antes de otimizar (ruff --select C90,PERF da o primeiro sinal barato)." ;;
esac
} > "$MSGF"

# CANAL (ADR 0021): stderr com exit 0 NAO chega ao modelo - fica so no `hook_success`,
# cujo `content` vem VAZIO. Medido por A/B com controle positivo e confirmado no
# trafego real. Aviso que precisa ser LIDO usa additionalContext; exit 2 fica para
# quem precisa BLOQUEAR. Nao voltar para `>&2`: o hook vira decoracao silenciosa.
jq -n --rawfile c "$MSGF" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}' 2>/dev/null
rm -f "$MSGF" 2>/dev/null
exit 0
