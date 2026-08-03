#!/usr/bin/env bash
# Hook PostToolUse - POKA-YOKE de erro obvio (CLAUDE.md secao 7): linta o arquivo de CODIGO recem
# escrito/editado (Write/Edit/MultiEdit/NotebookEdit) e, se houver erro obvio (import nao
# usado, simbolo indefinido, sintaxe), devolve o achado ao modelo via exit 2 (jidoka /
# stop-the-line: o modelo recebe o erro no stderr e corrige). Tira sintaxe/simbolo indefinido e
# deadcode da memoria e os torna barreira ativa (Shingo, poka-yoke).
#
# FAIL-OPEN por construcao: sem jq, sem linter para o tipo, ou arquivo inexistente -> exit 0.
# Um lint auxiliar NUNCA deve tijolar a escrita (distinto do artifact-discipline.sh, que e
# fail-CLOSED por ser guarda de seguranca). Cobertura honesta: Python (ruff>pyflakes>py_compile)
# e sintaxe JS (node --check). TS/TSX nao tem checagem standalone confiavel aqui -> ignorado.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
F="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || true)"
[ -n "$F" ] && [ -f "$F" ] || exit 0

OUT=""
case "$F" in
  */__init__.py)
    # F401 em __init__.py costuma ser re-export legitimo; checar so sintaxe/erros graves.
    if command -v ruff >/dev/null 2>&1; then
      OUT="$(ruff check --isolated --select E9 --quiet "$F" 2>&1 || true)"
    else
      OUT="$(python3 -m py_compile "$F" 2>&1 || true)"
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      # F = pyflakes (F401 import nao usado, F811 redefinicao, F821 indefinido, F841 var nao
      # usada...); E9 = erros de sintaxe. --isolated: ignora config do projeto, checa o universal.
      OUT="$(ruff check --isolated --select F,E9 --quiet "$F" 2>&1 || true)"
    elif python3 -c 'import pyflakes' >/dev/null 2>&1; then
      OUT="$(python3 -m pyflakes "$F" 2>&1 || true)"
    else
      OUT="$(python3 -m py_compile "$F" 2>&1 || true)"
    fi
    # REFERENCIA PENDENTE ENTRE ARQUIVOS (ADR 0015, achado 7 do refutador).
    # O ADR 0011 removeu o agente `continuidade` alegando que deadcode "e mecanizavel por hook".
    # Falso como estava: `ruff` NAO resolve nomes entre modulos. Repro:
    #   lib.py define apenas usada(); app.py faz `from lib import usada, removida`
    #   ruff --isolated app.py .......: All checks passed  (exit 0)
    #   ruff --select F,E9 . .........: All checks passed  (exit 0)
    #   mypy .........................: Module "lib" has no attribute "removida" [attr-defined]
    #   python3 -c "import app" ......: ImportError
    # mypy fecha a lacuna. Escopo deliberadamente ESTREITO - so a classe "referencia que nao
    # resolve" (has no attribute / is not defined). Nao se importa com tipagem do repo, para
    # nao inundar projeto legado sem anotacoes. --follow-imports=silent limita o relato ao
    # arquivo editado; timeout evita travar em monorepo.
    if command -v mypy >/dev/null 2>&1; then
      XREF="$(timeout 25 mypy --no-error-summary --ignore-missing-imports \
                 --follow-imports=silent --no-color-output "$F" 2>/dev/null \
              | grep -E 'has no attribute|is not defined' | head -5 || true)"
      [ -n "$XREF" ] && OUT="${OUT}${OUT:+
}REFERENCIA PENDENTE (nao resolve entre arquivos):
${XREF}"
    fi
    ;;
  *.js|*.mjs|*.cjs)
    command -v node >/dev/null 2>&1 && OUT="$(node --check "$F" 2>&1 || true)"
    ;;
  *)
    exit 0 ;;
esac

[ -z "$OUT" ] && exit 0

# Telemetria FAIL-SAFE + LOOP-GUARD (Refino C; R8 do agent-builder / Aider issue #1090): registra
# cada bloqueio e detecta REPETICAO do mesmo achado no mesmo arquivo. Falha de log nunca quebra o
# hook (|| true). Formato TSV: <iso-ts>\t<arquivo>\t<1a-linha-do-achado>. Relatorio: scripts/colegio-metrics.sh.
LOG="${HOME}/.claude/logs/poka-yoke-lint.log"
SIG="$(printf '%s' "$OUT" | head -1 | tr -d '\t')"
# Conta repeticoes RECENTES (ultimas 8 entradas) deste mesmo arquivo+achado, ANTES de logar a atual.
PRIOR=0
[ -f "$LOG" ] && PRIOR="$(tail -n 8 "$LOG" 2>/dev/null | awk -F'\t' -v f="$F" -v s="$SIG" '$2==f && $3==s' | wc -l | tr -d ' ')"
{ mkdir -p "$(dirname "$LOG")" 2>/dev/null && \
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null)" "$F" "$SIG" >> "$LOG"; } 2>/dev/null || true

{
  echo "Poka-yoke: erro obvio detectado em $F. Corrija antes de seguir:"
  printf '%s\n' "$OUT"
  # Loop-guard: NAO auto-libera (isso abriria buraco de deadcode); oferece a saida EXPLICITA e
  # revisavel (noqa + motivo) apos repeticao, em vez de oscilar indefinidamente (R8).
  if [ "${PRIOR:-0}" -ge 2 ]; then
    echo ""
    echo "ATENCAO - mesmo achado repetido ${PRIOR}x neste arquivo (loop-guard R8): se for padrao"
    echo "LEGITIMO (ex.: import intencional para efeito colateral, re-export), suprima de forma"
    echo "EXPLICITA e revisavel - adicione '# noqa: <codigo>' na linha COM um comentario do motivo -"
    echo "em vez de re-tentar. Se nao for legitimo, a correcao real continua necessaria. Sem auto-liberacao."
  fi
} >&2
exit 2
