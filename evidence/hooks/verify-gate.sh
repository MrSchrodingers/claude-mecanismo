#!/usr/bin/env bash
# CAMADA 1 - Hook Stop. GATE DE CONCLUSAO ancorado em EXECUCAO EXTERNA.
#
# Diferenca estrutural para a versao anterior: este hook NAO conhece linguagem nenhuma.
# Ele le `adapters/*.json`. Suportar C#, Java ou Elixir e ADICIONAR UM ARQUIVO - nunca editar
# este script. Era o acoplamento que tornava o global inutil fora de Python/JS.
#
# INVARIANTES (cada um pago com um defeito reproduzido - ver docs/falseamento):
#  1. Auto-deteccao roda APENAS `analyzer` (le codigo como dado). `test` executa codigo do
#     REPO e exige aprovacao de root. A versao anterior rodava pytest/npm test/manage.py
#     automaticamente: quatro repros criaram marcador em disco (classe CVE-2025-59536).
#  2. `.claude/verify-cmd` vem do repositorio: so executa com hash aprovado numa lista que
#     vive fora de qualquer repo E pertence a root.
#  3. Sem sha256sum -> FAIL-CLOSED. Hash vazio casaria com qualquer lista.
#  4. Sem upstream, so o nao-commitado. `HEAD~1..HEAD` acusava trabalho de sessao passada, e
#     gate que acusa sem motivo e desligado pelo usuario.
#  5. Throttle inclui hash do CONTEUDO: throttle so temporal mascara regressao nova.
#  6. Canal: exit 2 (bloqueia e entrega). stderr com exit 0 NAO chega ao modelo.
# Anti-loop: stop_hook_active. FAIL-OPEN a favor do usuario em erro proprio.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

ADAPTERS="${CLAUDE_ADAPTERS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../adapters" 2>/dev/null && pwd)}"
# INERCIA SILENCIOSA e o modo de falha que este projeto inteiro combate: um hook que nao acha
# a tabela saia 0 e ninguem saberia que o gate esta desligado. Encontrado ao testar - o
# mutante, copiado para /tmp, perdeu o caminho relativo e saiu sem dizer nada.
if [ ! -d "$ADAPTERS" ] || ! ls "$ADAPTERS"/*.json >/dev/null 2>&1; then
  { echo "GATE - tabela de adaptadores nao encontrada em '${ADAPTERS:-<vazio>}'."
    echo "O gate esta DESLIGADO neste turno. Defina CLAUDE_ADAPTERS_DIR ou instale a camada 1."
    echo "Estado: NAO VERIFICADO."
  } >&2
  exit 2
fi

command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

# --- o que mudou neste ciclo ---
UNCOMMITTED="$( { git -C "$ROOT" diff --name-only HEAD; git -C "$ROOT" ls-files --others --exclude-standard; } 2>/dev/null )"
UNPUSHED=""
if UP="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  UNPUSHED="$(git -C "$ROOT" diff --name-only "$UP"...HEAD 2>/dev/null)"
fi
CHANGED="$(printf '%s\n%s\n' "$UNCOMMITTED" "$UNPUSHED" | sed '/^$/d' | sort -u)"
[ -n "$CHANGED" ] || exit 0

# --- qual ecossistema? decidido pela TABELA, nao por conhecimento embutido ---
ECO=""; ADAPTER=""
for a in "$ADAPTERS"/*.json; do
  [ -f "$a" ] || continue
  # (a) algum arquivo de deteccao existe no root?
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    case "$d" in
      \**) ls "$ROOT"/$d >/dev/null 2>&1 && { ADAPTER="$a"; break; } ;;
      *)   [ -e "$ROOT/$d" ] && { ADAPTER="$a"; break; } ;;
    esac
  done < <(jq -r '.detect[]? // empty' "$a" 2>/dev/null)
  [ -n "$ADAPTER" ] && break
done
# (b) fallback: alguma extensao alterada casa com um adaptador?
if [ -z "$ADAPTER" ]; then
  for a in "$ADAPTERS"/*.json; do
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      printf '%s\n' "$CHANGED" | grep -qF -- "$e" && { ADAPTER="$a"; break; }
    done < <(jq -r '.extensoes[]? // empty' "$a" 2>/dev/null)
    [ -n "$ADAPTER" ] && break
  done
fi
[ -n "$ADAPTER" ] || exit 0
ECO="$(jq -r '.ecossistema // "?"' "$ADAPTER")"

# o diff tocou codigo DESTE ecossistema? (senao o gate nao tem o que dizer)
TOCOU=0
while IFS= read -r e; do
  [ -z "$e" ] && continue
  printf '%s\n' "$CHANGED" | grep -qF -- "$e" && TOCOU=1
done < <(jq -r '.extensoes[]? // empty' "$ADAPTER" 2>/dev/null)
[ "$TOCOU" = "1" ] || exit 0

# --- comando: verify-cmd aprovado > analyzer da tabela ---
VCMD=""; SRC=""
APPROVED="${HOME}/.claude/verify-cmd-approved"
if [ -f "$ROOT/.claude/verify-cmd" ]; then
  CAND="$(sed -n '1p' "$ROOT/.claude/verify-cmd" 2>/dev/null)"
  if [ -n "$CAND" ]; then
    CH="$(printf '%s' "$CAND" | sha256sum 2>/dev/null | cut -c1-16)"
    if [ -z "$CH" ]; then
      echo "GATE - sha256sum indisponivel; ignorando .claude/verify-cmd (fail-closed)." >&2
      CAND=""
    fi
    OWNER="$(stat -c '%U' "$APPROVED" 2>/dev/null || echo '')"
    if [ -n "$CAND" ] && [ -f "$APPROVED" ] && [ "$OWNER" = "root" ] \
       && grep -qE "(^|[[:space:]])${CH}([[:space:]]|$)" "$APPROVED" 2>/dev/null; then
      VCMD="$CAND"; SRC=".claude/verify-cmd (aprovado)"
    elif [ -n "$CAND" ]; then
      MOTIVO="nao aprovado"
      [ -f "$APPROVED" ] && [ "$OWNER" != "root" ] && MOTIVO="a lista de aprovacao pertence a '$OWNER', nao a root - sera IGNORADA"
      {
        echo "GATE - comando de verificacao do REPOSITORIO $MOTIVO. NAO foi executado."
        echo "Comando: $CAND"
        echo "Hash...: $CH"
        echo "Executa-lo sem aprovacao daria execucao de comando a qualquer repo clonado."
        echo "Se voce LEU o comando e ele e legitimo, o USUARIO aprova (caminho ABSOLUTO -"
        echo "dentro de 'sudo sh -c' o \$HOME e o de root; e apague o arquivo antes se ele"
        echo "existir com dono errado, porque append nao troca dono):"
        echo "  sudo sh -c 'echo \"$CH  # $(basename "$ROOT")\" >> $HOME/.claude/verify-cmd-approved && chown root:root $HOME/.claude/verify-cmd-approved'"
      } >&2
    fi
  fi
fi

if [ -z "$VCMD" ]; then
  VCMD="$(jq -r '.analyzer.cmd // empty' "$ADAPTER" 2>/dev/null)"
  SRC="analyzer[$ECO]"
  [ -n "$VCMD" ] || exit 0
  # analyzer por arquivo (ex.: node --check) precisa dos alvos
  if [ "$(jq -r '.analyzer.por_arquivo // false' "$ADAPTER")" = "true" ]; then
    ALVOS=""
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      ALVOS="$ALVOS $(printf '%s\n' "$CHANGED" | grep -F -- "$e" | while read -r f; do [ -f "$ROOT/$f" ] && printf '%q ' "$f"; done)"
    done < <(jq -r '.extensoes[]? // empty' "$ADAPTER")
    [ -n "${ALVOS// /}" ] || exit 0
    VCMD="for _f in$ALVOS; do $VCMD \"\$_f\" || exit 1; done"
  fi
fi

# --- throttle por projeto + conteudo ---
KEY="$(printf '%s' "$ROOT" | md5sum 2>/dev/null | cut -c1-12 || echo default)"
SIG="$( { printf '%s\n' "$CHANGED"; git -C "$ROOT" diff HEAD 2>/dev/null; } | md5sum 2>/dev/null | cut -c1-12 || echo x)"
STAMP="${HOME}/.claude/logs/.verifygate-${KEY}"
NOW="$(date +%s 2>/dev/null || echo 0)"; LAST=0; LASTSIG=""
[ -f "$STAMP" ] && { LAST="$(sed -n '1p' "$STAMP" 2>/dev/null || echo 0)"; LASTSIG="$(sed -n '2p' "$STAMP" 2>/dev/null || true)"; }
case "${NOW}x${LAST}" in *[!0-9x]*) NOW=0; LAST=0;; esac
[ "$NOW" -gt 0 ] && [ "$((NOW-LAST))" -lt 300 ] && [ "$SIG" = "$LASTSIG" ] && exit 0
{ mkdir -p "$(dirname "$STAMP")" 2>/dev/null && printf '%s\n%s\n' "$NOW" "$SIG" > "$STAMP"; } 2>/dev/null || true

# FERRAMENTA AUSENTE != VERIFICACAO FALHADA. Defeito encontrado ao testar este proprio hook
# num repo C# sem o SDK: `dotnet: command not found` (exit 127) barrava a conclusao como se o
# codigo estivesse quebrado. Barrar por falta de ferramenta e o falso positivo que faz o
# usuario desligar o gate - e ai ele nao protege mais nada.
BIN="$(printf '%s' "$VCMD" | awk '{print $1}')"
if [ -n "$BIN" ] && ! command -v "$BIN" >/dev/null 2>&1; then
  { echo "GATE - LACUNA DE COBERTURA, nao falha: o ecossistema detectado e '$ECO', mas '$BIN'"
    echo "nao esta no PATH. Nenhuma verificacao externa rodou neste turno."
    echo "Declare isso ao usuario: o estado e NAO VERIFICADO, nao verde."
    echo "Para cobrir: instale $BIN, ou defina o comando em $ROOT/.claude/verify-cmd e aprove."
  } >&2
  exit 2
fi

OUT="$(cd "$ROOT" && timeout 180 sh -c "$VCMD" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && exit 0
# 127 tambem pode vir de binario interno ao comando composto
if [ "$RC" -eq 127 ]; then
  { echo "GATE - LACUNA DE COBERTURA (exit 127: comando nao encontrado), nao falha de codigo."
    echo "Ecossistema: $ECO | Comando: $VCMD"
    printf '%s\n' "$OUT" | tail -5
    echo "O estado e NAO VERIFICADO. Nao declare verde nem vermelho - declare a lacuna."
  } >&2
  exit 2
fi

{
  echo "GATE DE CONCLUSAO - verificacao FALHOU (exit=$RC). NAO esta pronto."
  echo "Ecossistema: $ECO | Fonte: $SRC"
  echo "Comando....: $VCMD"
  printf '%s\n' "$OUT" | tail -25
  echo "---"
  echo "O sinal EXTERNO nao passou. Nao declare corrigido a partir de auto-avaliacao."
  if [ "$SRC" != ".claude/verify-cmd (aprovado)" ]; then
    TESTCMD="$(jq -r '.test.cmd // empty' "$ADAPTER" 2>/dev/null)"
    [ -n "$TESTCMD" ] && echo "Nota: isto e o ANALISADOR. A suite deste projeto ($TESTCMD) executa codigo do repo e so roda com aprovacao."
  fi
} >&2
exit 2
