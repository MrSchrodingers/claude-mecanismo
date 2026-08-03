#!/usr/bin/env bash
# PLANO DE EVIDENCIA - verifica o snapshot e registra o veredito no ledger.  Hook: Stop.
#
# O QUE ESTE HOOK NAO E, e por que a reescrita:
# Ele NAO e o portao de conclusao. `Stop` nao pode ser fronteira de confianca, por quatro
# razoes independentes, todas verificadas:
#   - `stop_hook_active=true` na parada seguinte a um bloqueio (semantica anti-loop oficial);
#   - o runtime SOBREPOE o hook apos N bloqueios consecutivos (default 8);
#   - esse N vive em CLAUDE_CODE_STOP_HOOK_BLOCK_CAP, dentro do settings.json que o proprio
#     ator governado pode escrever - politica no espaco de escrita do governado nao e politica;
#   - `Stop` nao dispara quando o usuario interrompe a sessao nem em falha de API.
# Logo este hook produz no maximo um CANDIDATO e um registro auditavel. Quem certifica e a CI
# sobre o SHA exato, sob politica que o ator nao pode alterar.  Ver docs/adr/0022.
#
# INVARIANTES (cada um pago com defeito REPRODUZIDO - tests/unit/regressao-gate.sh):
#  G1. O cache guarda VEREDITO, nao carimbo. `pass` do mesmo snapshot e reutilizavel; `fail`
#      jamais vira verde. A versao anterior gravava (timestamp, assinatura) ANTES de executar:
#      a segunda parada dentro de 5 min achava a assinatura e saia 0 com o codigo quebrado.
#  G2. `stop_hook_active` nao pode ser verde silencioso. stderr com exit 0 NAO chega ao modelo
#      (docs/adr/0021); quem avisa sem bloquear usa additionalContext.
#  G3. A identidade e sobre BYTES. Nome nao identifica estado: a versao anterior hasheava
#      nomes + `git diff HEAD`, e `git diff` nao enxerga conteudo de arquivo untracked.
#  G4. Conjuncao sobre TODOS os adaptadores aplicaveis: Ready(x) = AND Pass(a,x). A anterior
#      parava no primeiro que casava - monorepo com JS valido e Python quebrado passava verde.
#  G5. Sem `sh -c`. O adaptador declara exec.command + exec.args[]; o executor decide o que
#      roda. String interpretada por shell permite redirecao, substituicao e composicao.
#  G6. Ferramenta ausente e LACUNA declarada, nao falha de codigo. Falso bloqueio e o que faz
#      o operador desligar o gate - e gate desligado protege zero.
#  G7. Tabela ausente e FAIL-CLOSED com aviso. Inercia silenciosa e o modo de falha que este
#      projeto inteiro combate.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
ADAPTERS="${CLAUDE_ADAPTERS_DIR:-$(cd "$HERE/../../execution/adapters/code" 2>/dev/null && pwd)}"
LEDGER_DIR="${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}"

# CANAIS (docs/adr/0021): exit 2 bloqueia e entrega; additionalContext avisa e nao bloqueia;
# stderr com exit 0 e inerte - nunca usar para informacao que precisa chegar.
aviso(){ jq -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$c}}' 2>/dev/null; exit 0; }
barra(){ printf '%s\n' "$1" >&2; exit 2; }
# Quando o runtime ja esta em continuacao forcada, bloquear nao e opcao: avisa.
reporta(){ if [ "$ACTIVE" = "true" ]; then aviso "$1"; else barra "$1"; fi; }

command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

# --- o que mudou: nao-commitado + untracked + commits nao publicados ---
UPSTREAM="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
CHANGED="$( { git -C "$ROOT" diff --name-only HEAD 2>/dev/null
              git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null
              [ -n "$UPSTREAM" ] && git -C "$ROOT" diff --name-only "${UPSTREAM}...HEAD" 2>/dev/null
            } | sed '/^$/d' | sort -u )"
[ -n "$CHANGED" ] || exit 0

# --- G7: tabela ausente e fail-closed ---
if [ ! -d "$ADAPTERS" ] || ! ls "$ADAPTERS"/*.json >/dev/null 2>&1; then
  reporta "GATE - tabela de adaptadores nao encontrada em '${ADAPTERS:-<vazio>}'.
O verificador esta DESLIGADO neste turno. Estado: NAO VERIFICADO.
Defina CLAUDE_ADAPTERS_DIR ou rode install/apply.sh."
fi

# --- G4: TODO adaptador cuja extensao foi tocada e aplicavel (nao so o primeiro) ---
APLICAVEIS=(); ECOS=""
for a in "$ADAPTERS"/*.json; do
  [ -f "$a" ] || continue
  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    if printf '%s\n' "$CHANGED" | grep -q -- "${ext}\$"; then
      APLICAVEIS+=("$a"); ECOS="$ECOS $(jq -r '.ecosystem // "?"' "$a")"; break
    fi
  done < <(jq -r '.extensions[]? // empty' "$a" 2>/dev/null)
done
[ "${#APLICAVEIS[@]}" -gt 0 ] || exit 0

# --- G3: identidade sobre BYTES do estado avaliado ---
sha(){ sha256sum 2>/dev/null | cut -c1-32; }
SNAPSHOT="$( {
    printf 'head %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
    [ -n "$UPSTREAM" ] && git -C "$ROOT" rev-list "${UPSTREAM}..HEAD" 2>/dev/null
    printf '%s\n' "$CHANGED" | while IFS= read -r f; do
      if [ -f "$ROOT/$f" ]; then printf '%s %s\n' "$f" "$(sha256sum "$ROOT/$f" 2>/dev/null | cut -d' ' -f1)"
      else printf '%s absent\n' "$f"; fi
    done
  } | sha )"
VERIFIERS="$(for a in "${APLICAVEIS[@]}"; do cat "$a"; done | sha)"
ENVD="$(for a in "${APLICAVEIS[@]}"; do
          c="$(jq -r '.exec.command' "$a")"; printf '%s=%s\n' "$c" "$(command -v "$c" 2>/dev/null || echo absent)"
        done | sha)"
# G3/G1: sem sha256sum a identidade e vazia e casaria com tudo -> fail-closed.
if [ -z "$SNAPSHOT" ] || [ -z "$VERIFIERS" ]; then
  reporta "GATE - sha256sum indisponivel; a identidade do snapshot nao pode ser calculada.
Estado: NAO VERIFICADO (fail-closed)."
fi

# --- G1: ledger append-only; so `pass` do MESMO snapshot e reutilizavel ---
KEY="$(printf '%s' "$ROOT" | sha)"
LEDGER="$LEDGER_DIR/${KEY}.jsonl"
mkdir -p "$LEDGER_DIR" 2>/dev/null || true
PRIOR="$(grep -F "\"snapshot\":\"$SNAPSHOT\"" "$LEDGER" 2>/dev/null \
         | grep -F "\"verifiers\":\"$VERIFIERS\"" | grep -F "\"env\":\"$ENVD\"" | tail -1)"
if [ -n "$PRIOR" ] && [ "$(printf '%s' "$PRIOR" | jq -r '.verdict' 2>/dev/null)" = "pass" ]; then
  exit 0   # mesmo snapshot, mesmos verificadores, mesmo ambiente, veredito aprovado
fi
# veredito anterior `fail` ou `gap` NAO e reutilizado: reexecuta. Nunca vira verde por cache.

registra(){  # $1=verdict $2=detalhe
  jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" --arg s "$SNAPSHOT" \
         --arg v "$VERIFIERS" --arg e "$ENVD" --arg d "$1" --arg m "$2" \
         '{ts:$t,snapshot:$s,verifiers:$v,env:$e,verdict:$d,detail:$m}' >> "$LEDGER" 2>/dev/null || true
}

# --- G5: execucao por command + args, sem shell ---
FALHAS=""; LACUNAS=""; SAIDA=""
for a in "${APLICAVEIS[@]}"; do
  ID="$(jq -r '.id // "?"' "$a")"; ECO="$(jq -r '.ecosystem // "?"' "$a")"
  CMD="$(jq -r '.exec.command' "$a")"
  TMO="$(jq -r '.limits.timeout_seconds // 120' "$a")"
  if ! command -v "$CMD" >/dev/null 2>&1; then
    LACUNAS="$LACUNAS
  - $ID: '$CMD' nao esta no PATH (ecossistema $ECO)"; continue
  fi
  mapfile -t ARGS < <(jq -r '.exec.args[]? // empty' "$a" 2>/dev/null)
  if [ "$(jq -r '.per_file // false' "$a")" = "true" ]; then
    RC=0; OUT=""
    while IFS= read -r ext; do
      [ -z "$ext" ] && continue
      while IFS= read -r f; do
        [ -f "$ROOT/$f" ] || continue
        O="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" "$f" 2>&1)" || { RC=1; OUT="$OUT
$O"; }
      done < <(printf '%s\n' "$CHANGED" | grep -- "${ext}\$" || true)
    done < <(jq -r '.extensions[]? // empty' "$a")
  else
    OUT="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>&1)"; RC=$?
  fi
  if [ "$RC" -eq 127 ]; then
    LACUNAS="$LACUNAS
  - $ID: binario interno ausente (exit 127)"; continue
  fi
  if [ "$RC" -ne 0 ]; then
    FALHAS="$FALHAS $ID"
    SAIDA="$SAIDA
--- $ID ($ECO) exit=$RC ---
$(printf '%s\n' "$OUT" | tail -12)"
  fi
done

# --- veredito conjuntivo ---
if [ -n "$FALHAS" ]; then
  registra "fail" "falharam:$FALHAS"
  reporta "GATE - VERIFICACAO FALHOU. O snapshot NAO e um candidato valido.
Verificadores aplicados:$ECOS
Reprovaram:$FALHAS
$SAIDA
---
Estado: NOT_VERIFIED. O sinal e externo - nao declare corrigido por auto-avaliacao.
Este hook nao certifica nada: mesmo passando, o veredito final e da CI sobre o SHA."
fi
if [ -n "$LACUNAS" ]; then
  registra "gap" "lacunas:$LACUNAS"
  reporta "GATE - LACUNA DE COBERTURA, nao falha de codigo.$LACUNAS
Nenhuma verificacao externa cobriu esses caminhos neste turno.
Estado: NAO VERIFICADO - declare a lacuna ao usuario. Nao diga verde nem vermelho."
fi
registra "pass" "verificadores:$ECOS"
exit 0
