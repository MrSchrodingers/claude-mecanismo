#!/usr/bin/env bash
# RAIZ DE CONFIANCA - fase 2. Instala a politica FORA do espaco de escrita do ator governado.
#
# O PROBLEMA QUE ISTO RESOLVE. Ate aqui, `install/apply.sh` grava em `~/.claude`, que o ator
# governado escreve. Isso detecta drift ACIDENTAL e nada mais: contra intencao, o ator apaga o
# hook, edita o `settings.json`, ou muda `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. Parametro de
# politica dentro do espaco de escrita do governado nao e politica (ADR 0022).
#
# O QUE PRECISA SER ROOT-OWNED, e por que nao basta o hook. Verificado no codigo:
#   hooks (14)      - a politica em si;
#   adapters (11)   - `verify-gate.sh` le a tabela em `$CLAUDE_ADAPTERS_DIR`. Se ela for
#                     gravavel pelo ator, ele desliga o gate esvaziando o diretorio (o proprio
#                     G5 mostra que tabela vazia e fail-closed, mas um adaptador ADULTERADO
#                     passaria); e `doctool.sh` le `$DOC_ADAPTERS_DIR`;
#   doctools (5)    - `read-budget.sh` os executa.
# Politica root-owned lendo tabela user-owned e raiz de confianca so no nome.
#
# O QUE NAO E COBERTO, declarado: agentes (10) e skills (9) seguem em `~/.claude`. Nao sao
# politica - sao capacidade. O ator pode edita-los; o que ele NAO pode e desativar o hook que
# cobra o contrato de retorno deles.
#
# ARMADILHA CENTRAL, confirmada na documentacao primaria antes de qualquer escrita:
#   "allowManagedHooksOnly | (Managed settings only) Only managed hooks, SDK hooks, and hooks
#    from plugins force-enabled in managed settings `enabledPlugins` are loaded. User, project,
#    and all other plugin hooks are blocked."
# Ou seja, ativar isso ANTES de os 14 hooks existirem no escopo managed derruba o mecanismo
# inteiro. Por isso o deploy e a ativacao sao PASSOS SEPARADOS, e `--enforce` recusa rodar se a
# conformidade do escopo managed nao passar.
#
# TESTABILIDADE: `MANAGED_PREFIX` desloca a raiz (default `/`). Toda a logica - copia, digest,
# geracao do JSON, verificacao, reversao - roda sem privilegio contra um prefixo temporario, e
# e isso que `tests/unit/managed.sh` exercita. Com prefixo `/` exige root, e so ai a posse por
# root e verificada.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
# MANAGED_MANIFEST e override SO PARA TESTE: `tests/unit/managed.sh` precisa exercitar o caso
# "deploy incompleto" sem mutar o manifesto real - se a suite morresse no meio, o repositorio
# ficaria com o manifesto sabotado no disco.
MAN="${MANAGED_MANIFEST:-install/manifest.lock}"
PREFIX="${MANAGED_PREFIX:-/}"
PREFIX="${PREFIX%/}"                 # normaliza: "/" vira "", evitando "//etc"
OPT="$PREFIX/opt/evidence-gate"
ETC="$PREFIX/etc/claude-code"
SETTINGS="$ETC/managed-settings.json"
REAL=0; [ -z "$PREFIX" ] && REAL=1   # prefixo vazio = raiz de verdade

MODO="deploy"
case "${1:-}" in
  --dry-run) MODO="dry" ;;
  --enforce) MODO="enforce" ;;
  --revert)  MODO="revert" ;;
  --verify)  MODO="verify" ;;
  "")        MODO="deploy" ;;
  *) echo "uso: $0 [--dry-run|--enforce|--revert|--verify]" >&2; exit 64 ;;
esac

if [ "$REAL" -eq 1 ] && [ "$MODO" != "dry" ] && [ "$MODO" != "verify" ] && [ "$(id -u)" -ne 0 ]; then
  echo "ERRO: '$MODO' sobre a raiz real exige root. Rode com sudo, ou use MANAGED_PREFIX=<dir> para ensaiar." >&2
  exit 77
fi
[ -f "$MAN" ] || { echo "ERRO: $MAN ausente - rode install/manifest.sh" >&2; exit 1; }

# destino de cada componente dentro de $OPT. `hooks/x.sh` fica `hooks/x.sh`; os demais vem com
# o prefixo `evidence-gate/` do layout de ~/.claude, que aqui e redundante e sai.
destino_managed(){ printf '%s\n' "${1#evidence-gate/}"; }

# tipos que compoem a POLITICA. agent e skill ficam de fora por decisao declarada no cabecalho.
tipos_politica(){ awk -F'\t' '!/^#/ && ($1=="hook" || $1=="adapter" || $1=="doctool")' "$MAN"; }

plano(){
  tipos_politica | while IFS=$'\t' read -r tipo origem destino _sha; do
    printf '  %-8s %s -> %s/%s\n' "$tipo" "$origem" "$OPT" "$(destino_managed "$destino")"
  done
}

if [ "$MODO" = "dry" ]; then
  echo "PLANO (nada sera escrito). prefixo='${PREFIX:-/}'"
  plano
  n=$(tipos_politica | wc -l)
  echo "  $n componentes de politica; settings managed em $SETTINGS"
  echo "  allowManagedHooksOnly: NAO seria ativado neste modo (use --enforce, depois de verificar)"
  exit 0
fi

if [ "$MODO" = "revert" ]; then
  # Remove SOMENTE o que este script cria. Nunca toca em caminho desconhecido.
  if [ -f "$SETTINGS" ]; then rm -f "$SETTINGS"; echo "removido: $SETTINGS"; fi
  if [ -f "$SETTINGS.pre-evidence-gate" ]; then
    mv -f "$SETTINGS.pre-evidence-gate" "$SETTINGS"; echo "restaurado o managed-settings.json anterior"
  fi
  if [ -d "$OPT" ]; then rm -rf "$OPT"; echo "removido: $OPT"; fi
  rmdir "$ETC" 2>/dev/null && echo "removido (vazio): $ETC"
  echo "REVERTIDO. Os hooks de escopo de usuario em ~/.claude voltam a valer."
  exit 0
fi

conformidade_managed(){   # ecoa "ok N" ou lista divergencias; nunca escreve
  local div=0 n=0 dono_ruim=0 grav=0
  while IFS=$'\t' read -r _tipo origem destino sha; do
    n=$((n+1))
    local alvo="$OPT/$(destino_managed "$destino")"
    if [ ! -e "$alvo" ]; then echo "  AUSENTE  $alvo"; div=$((div+1)); continue; fi
    local d
    if [ -d "$alvo" ]; then d="$(cd "$alvo" && find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)"
    else d="$(sha256sum "$alvo" | cut -d' ' -f1)"; fi
    [ "$d" = "$sha" ] || { echo "  DIVERGE  $alvo"; div=$((div+1)); }
    if [ "$REAL" -eq 1 ]; then
      [ "$(stat -c '%U' "$alvo")" = "root" ] || { echo "  DONO!=root  $alvo"; dono_ruim=$((dono_ruim+1)); }
      # o ponto inteiro da fase 2: o ator governado nao pode reescrever a politica
      [ -w "$alvo" ] && [ "$(id -u)" -ne 0 ] && { echo "  GRAVAVEL pelo ator  $alvo"; grav=$((grav+1)); }
    fi
  done < <(tipos_politica)
  echo "RESUMO $n $div $dono_ruim $grav"
}

if [ "$MODO" = "verify" ]; then
  out="$(conformidade_managed)"; printf '%s\n' "$out" | grep -v '^RESUMO' || true
  read -r _ n div dono grav <<<"$(printf '%s\n' "$out" | grep '^RESUMO')"
  printf 'managed: %s componentes | %s divergentes | %s com dono errado | %s gravaveis pelo ator\n' \
         "$n" "$div" "$dono" "$grav"
  if [ -f "$SETTINGS" ]; then
    printf 'allowManagedHooksOnly=%s\n' "$(jq -r '.allowManagedHooksOnly // false' "$SETTINGS" 2>/dev/null)"
  else
    echo "managed-settings.json AUSENTE"; exit 1
  fi
  [ "$div" -eq 0 ] && [ "$dono" -eq 0 ] && [ "$grav" -eq 0 ] || exit 1
  echo "ESTADO: politica fora do espaco de escrita do ator"
  exit 0
fi

# ---------------------------------------------------------------- deploy / enforce
mkdir -p "$OPT" "$ETC" || exit 1
while IFS=$'\t' read -r _tipo origem destino _sha; do
  alvo="$OPT/$(destino_managed "$destino")"
  mkdir -p "$(dirname "$alvo")"
  if [ -d "$origem" ]; then rm -rf "$alvo"; cp -a "$origem" "$alvo"
  else cp -f "$origem" "$alvo"; fi
  case "$alvo" in *.sh|*/document-tools/*) chmod 0755 "$alvo" ;; *) chmod 0644 "$alvo" ;; esac
done < <(tipos_politica)
find "$OPT" -type d -exec chmod 0755 {} + 2>/dev/null || true
if [ "$REAL" -eq 1 ]; then chown -R root:root "$OPT"; fi

# --- PORTAO ANTES DA ESCRITA DA POLITICA -------------------------------------------------
# ORDEM DELIBERADA, e o motivo e um defeito que este repositorio ja pagou. Na primeira versao
# deste script a conformidade era conferida DEPOIS de gravar o `managed-settings.json`. Com
# `--enforce` isso significa: a flag que bloqueia TODO hook de usuario e de plugin ja estaria
# no disco quando a checagem reprovasse - deixando o sistema sem os hooks managed (deploy
# incompleto) E sem os de usuario (bloqueados). O mecanismo inteiro cairia, que e exatamente a
# armadilha que o handoff nomeia.
# E a MESMA classe do defeito do `--dry-run` (ADR 0022, adendo 2): a garantia nova estava
# correta e mal posicionada em relacao a escrita. Acrescentar garantia nao prova que os modos
# existentes continuam seguros.
echo "=== conformidade do escopo managed (ANTES de escrever a politica) ==="
out="$(conformidade_managed)"; printf '%s\n' "$out" | grep -v '^RESUMO' || true
read -r _ n div dono grav <<<"$(printf '%s\n' "$out" | grep '^RESUMO')"
printf 'managed: %s componentes | %s divergentes | %s com dono errado | %s gravaveis pelo ator\n' \
       "$n" "$div" "$dono" "$grav"
if [ "$div" -ne 0 ] || [ "$dono" -ne 0 ] || [ "$grav" -ne 0 ]; then
  echo "ERRO: deploy incompleto - a politica NAO foi escrita e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      O estado anterior permanece intacto." >&2
  exit 1
fi

# --- managed-settings.json, a partir da MESMA especificacao que o escopo de usuario ---
ENFORCE=false; [ "$MODO" = "enforce" ] && ENFORCE=true
# base = "$OPT/hooks", nao literal "/opt/...": sob prefixo de ensaio o JSON precisa apontar
# para os arquivos que de fato existem, senao o teste nao pode conferir que o caminho declarado
# corresponde a um hook presente - e essa checagem e justamente a que impede ativar apontando
# para o vazio.
HOOKS_JSON="$(bash install/hooks-spec.sh "$OPT/hooks")" || exit 1
# BACKUP SO DO QUE NAO E NOSSO. Defeito encontrado por MG8: a condicao era apenas "existe e
# ainda nao ha backup", entao a SEGUNDA execucao (deploy e depois --enforce) tratava o arquivo
# que o proprio instalador havia escrito como se fosse pre-existente. O `--revert` seguinte
# restaurava esse "backup" e recriava a politica - reversao que nao reverte, que e pior do que
# nao ter reversao, porque o operador acredita ter voltado ao estado anterior.
# A marca `_managed_by` responde "este arquivo e nosso?" sem depender de heuristica.
if [ -f "$SETTINGS" ] && [ ! -f "$SETTINGS.pre-evidence-gate" ] \
   && ! jq -e '._managed_by == "evidence-gate"' "$SETTINGS" >/dev/null 2>&1; then
  cp -f "$SETTINGS" "$SETTINGS.pre-evidence-gate"
fi
TMP="$(mktemp)"
if jq -n --argjson h "$HOOKS_JSON" --argjson enf "$ENFORCE" --arg rp "$REPO" \
      --arg ad "$OPT/adapters/code" --arg dd "$OPT/adapters/documents" \
      '{_managed_by:"evidence-gate", allowManagedHooksOnly:$enf, hooks:$h,
        env:{CLAUDE_ADAPTERS_DIR:$ad, DOC_ADAPTERS_DIR:$dd, EVIDENCE_GATE_REPO:$rp}}' \
      > "$TMP" && jq -e . "$TMP" >/dev/null; then
  cp -f "$TMP" "$SETTINGS"; rm -f "$TMP"; chmod 0644 "$SETTINGS"
  [ "$REAL" -eq 1 ] && chown root:root "$SETTINGS"
else
  rm -f "$TMP"; echo "ERRO: managed-settings.json nao pode ser gerado - nada foi alterado nele" >&2; exit 1
fi

if [ "$MODO" = "enforce" ]; then
  echo "allowManagedHooksOnly=true - hooks de escopo de USUARIO e de PLUGIN estao agora bloqueados."
  echo "Reverter: sudo bash install/apply-managed.sh --revert"
else
  echo "allowManagedHooksOnly=false - por enquanto os hooks managed SOMAM aos de usuario."
  echo "Cada hook rodara DUAS vezes ate a ativacao. Isso e esperado e mensuravel; e o passo que"
  echo "prova que o escopo managed carregou ANTES de desligar o escopo de usuario."
fi
