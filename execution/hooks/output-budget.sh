#!/usr/bin/env bash
# Hook PostToolUse (Bash) - ORCAMENTO DE SAIDA DE FERRAMENTA. ADRs 0017 e 0020.
#
# Medido em 40 transcripts (190,4 MB): superficie de ferramenta 43,7% do orcamento; a prosa,
# 4,8%. Encurtar prosa tem teto de ~5%; o orcamento esta aqui.
#
# INVARIANTES (mudar qualquer um ja causou inercia silenciosa - ver ADR 0020):
#  1. updatedToolOutput e OBJETO {stdout,stderr,interrupted}, nunca string. O runtime rejeita
#     string e a saida passa intacta - o hook fica inerte SEM erro visivel.
#  2. O `-i` do grep de veredito NAO e opcional: ERROR/FAILED/Traceback sao as formas reais.
#  3. NAO usar `case` com $'\x00': bash nao guarda NUL em variavel, o padrao vira `**` e casa
#     com tudo. Deteccao de binario fica com grep -P sobre o fluxo.
#  4. --rawfile, nunca --arg: --arg estoura E2BIG acima de ~128 KB e emite 0 byte.
#  5. Quebra de linha antes do rodape: sem ela o rodape corrompe a ultima linha, que e onde
#     costuma estar o veredito.
#  6. Se o resultado ficar >= ao original, NAO alterar (evita inflacao em saida de linha unica).
# Corta o MEIO, preserva cabeca, cauda e toda linha de veredito. FAIL-OPEN.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"

OUT="$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // ""' 2>/dev/null || true)"
ERRTXT="$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // ""' 2>/dev/null || true)"
INTER="$(printf '%s' "$INPUT" | jq -r 'if (.tool_response.interrupted // false) then "true" else "false" end' 2>/dev/null || echo false)"
[ -n "$OUT" ] || exit 0

LIM=${CLAUDE_OUTPUT_BUDGET:-12000}
SZ=${#OUT}
[ "$SZ" -le "$LIM" ] && exit 0

# m3 - saida binaria: nao cortar. A substituicao de comando ja descartou NULs, entao qualquer
# recorte aqui produziria algo diferente do original sem avisar.
#
# ARMADILHA CORRIGIDA: a 1a versao desta guarda usava
#   case "$OUT" in *$'\x01'*|*$'\x02'*|*$'\x00'*) exit 0 ;; esac
# Bash NAO consegue armazenar NUL numa variavel, entao `$'\x00'` expande para string VAZIA e
# o padrao vira `**`, que casa com QUALQUER coisa. O hook saia no primeiro case, sempre - o
# efeito era um segundo modo de inercia, dentro da correcao do primeiro. Um caractere de
# escape invisivel desligou o mecanismo inteiro, e so o `bash -x` mostrou.
# Deteccao fica so com grep -P, que opera sobre o fluxo de bytes e nao sobre variavel.
printf '%s' "$OUT" | grep -qP '[\x00-\x08\x0e-\x1f]' 2>/dev/null && exit 0

TMP="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$TMP" "$TMP.n" 2>/dev/null' EXIT
printf '%s' "$OUT" > "$TMP"

NL=$(wc -l < "$TMP" 2>/dev/null || echo 0)
HEAD_N=60; TAIL_N=40

if [ "$NL" -lt $((HEAD_N + TAIL_N + 10)) ]; then
  # M3 - poucas linhas: cortar por BYTE, senao head/tail devolveria quase tudo e o rodape
  # INFLARIA a saida. Metade do orcamento em cada ponta.
  H=$((LIM / 2)); T=$((LIM / 4))
  {
    head -c "$H" "$TMP"
    printf '\n[... %s bytes elididos pelo orcamento de saida (corte por byte: a saida tem %s linhas, poucas para corte por linha) ...]\n' "$((SZ - H - T))" "$NL"
    tail -c "$T" "$TMP"
    printf '\n[orcamento de saida: original %s B, limite %s B. Reexecute o comando estreitado se precisar do trecho completo.]\n' "$SZ" "$LIM"
  } > "$TMP.n"
else
  MEIO_INI=$((HEAD_N + 1)); MEIO_FIM=$((NL - TAIL_N))
  SINAL="$(sed -n "${MEIO_INI},${MEIO_FIM}p" "$TMP" 2>/dev/null \
           | grep -inE 'error|erro|fail|falha|traceback|exception|fatal|panic|denied|refused|timeout|exit code|assert' 2>/dev/null || true)"
  # O `-i` NAO e opcional: `ERROR`, `FAILED` e `Traceback` sao as formas que aparecem na vida
  # real. Ele foi perdido numa reescrita e a preservacao de veredito parou de funcionar em
  # silencio - o hook cortava o meio E descartava o erro que estava nele.
  # `grep -c . || echo 0` emitia "0\n0" quando nao havia match: grep -c IMPRIME 0 e ainda
  # sai 1, entao o `|| echo 0` concatenava um segundo zero e o `[ ... -gt ]` seguinte
  # quebrava com "integer expected".
  N_SINAL=$(printf '%s' "$SINAL" | grep -c . 2>/dev/null); N_SINAL=${N_SINAL:-0}
  case "$N_SINAL" in *[!0-9]*) N_SINAL=0 ;; esac
  # m2 - renumerar para linha ABSOLUTA do arquivo original, senao a instrucao de reexecutar
  # com `sed -n 'X,Yp'` aponta para a linha errada.
  # Sem -F: e sem atribuir $1: atribuir a um campo faz o awk RECONSTRUIR $0 usando OFS (espaco),
  # o que destruia o formato "N:texto" e fazia o sub() seguinte nao casar. Recorta pelo indice
  # do primeiro ':' e reconstroi a mao.
  SINAL_ABS="$(printf '%s' "$SINAL" | head -25 | awk -v off="$HEAD_N" \
      '{ n = index($0, ":"); if (n > 0) print (substr($0,1,n-1) + off) ":" substr($0,n+1); else print }' 2>/dev/null || true)"
  {
    head -n "$HEAD_N" "$TMP"
    if [ "$N_SINAL" -gt 0 ]; then
      printf '[... linhas %s-%s elididas; %s linha(s) de VEREDITO preservadas abaixo' "$MEIO_INI" "$MEIO_FIM" "$N_SINAL"
      [ "$N_SINAL" -gt 25 ] && printf ' (mostrando as 25 primeiras de %s - reexecute com grep para ver todas)' "$N_SINAL"
      printf ' ...]\n%s\n' "$SINAL_ABS"
    else
      printf '[... linhas %s-%s elididas; nenhuma linha de erro/falha nelas ...]\n' "$MEIO_INI" "$MEIO_FIM"
    fi
    tail -n "$TAIL_N" "$TMP"
    # a ultima linha pode nao terminar em \n (a substituicao de comando o remove); sem isto o
    # rodape cola nela e CORROMPE a ultima linha - onde costuma estar o veredito.
    [ -n "$(tail -c 1 "$TMP")" ] && printf '\n'
    printf '[orcamento de saida: original %s B / %s linhas, limite %s B. Precisa do trecho completo? Reexecute estreitado, ex.: sed -n %s,%sp]\n' "$SZ" "$NL" "$LIM" "$MEIO_INI" "$MEIO_FIM"
  } > "$TMP.n"
fi

# M4 - --rawfile evita E2BIG (jq --arg com centenas de KB estoura MAX_ARG_STRLEN e emite 0 B).
# Segunda trava: se mesmo assim o resultado ficou maior que o original, nao alterar nada.
NEWSZ=$(wc -c < "$TMP.n" 2>/dev/null || echo 0)
[ "$NEWSZ" -ge "$SZ" ] && exit 0

jq -n --rawfile o "$TMP.n" --arg e "$ERRTXT" --argjson i "$INTER" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",
    updatedToolOutput:{stdout:$o, stderr:$e, interrupted:$i}}}' 2>/dev/null || exit 0
exit 0
