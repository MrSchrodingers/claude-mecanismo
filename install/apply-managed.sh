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
# CANONICALIZA o prefixo: sem isto, `MANAGED_PREFIX=/tmp/x/opt/..` faz $OPT conter `..` e a
# checagem de confinamento abaixo comparara prefixos textuais que nao correspondem ao caminho
# real. `realpath -m` resolve sem exigir que o caminho exista.
if [ -n "$PREFIX" ]; then
  PREFIX="$(realpath -m "$PREFIX" 2>/dev/null || printf '%s' "$PREFIX")"
  PREFIX="${PREFIX%/}"
fi
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

# ===================== CONFINAMENTO DE CAMINHO (auditoria de 2026-08-04) =====================
# DEFEITO CRITICO CORRIGIDO, com PoC executada. O manifesto e um ARQUIVO DO REPOSITORIO, isto e,
# esta dentro do espaco de escrita do ator governado. Suas colunas `origem` e `destino` eram
# usadas VERBATIM como caminho de `mkdir -p`, `cp -f` e `rm -rf`, e este script roda como ROOT.
# Medido, com prefixo temporario:
#
#   destino = ../../../ZONA_PROIBIDA/vitima.conf   -> arquivo FORA do prefixo sobrescrito
#   destino = ../../../ZONA_PROIBIDA  (origem=dir) -> `rm -rf` destruiu o diretorio FORA do prefixo
#
# Sob `sudo`, isso e escrita e remocao arbitrarias como root a partir de dado que o ator
# controla: `/etc/cron.d/`, `/etc/sudoers.d/`, `~/.ssh/authorized_keys`. A raiz de confianca
# seria instalada a partir de entrada nao confiavel - a inversao exata da tese deste projeto.
#
# O DIGEST NAO PROTEGE. `install/manifest.sh` calcula o sha256 do MESMO working tree que
# deveria proteger, e o loop de deploy descartava a coluna. A conformidade compara o arquivo
# copiado com o valor que o proprio atacante escreveu. E detector de drift contra `~/.claude`,
# nunca controle de integridade sobre o repositorio - e essa distincao passou despercebida ate
# a auditoria.
#
# A regra e REJEITAR A LINHA E ABORTAR, nunca sanear: sanear um caminho hostil deixa a duvida
# sobre o que sobrou, e num contexto root a duvida nao e aceitavel.
confinado(){ # $1=caminho candidato  $2=raiz que deve conte-lo -> 0 se dentro
  local c r
  c="$(realpath -m "$1" 2>/dev/null)" || return 1
  r="$(realpath -m "$2" 2>/dev/null)" || return 1
  case "$c" in "$r"|"$r"/*) return 0 ;; *) return 1 ;; esac
}

valida_manifesto(){ # ecoa violacoes; retorna != 0 se houver qualquer uma
  local ruins=0 tipo origem destino _sha
  while IFS=$'\t' read -r tipo origem destino _sha; do
    # 1. forma. Rejeita absoluto e qualquer componente `..` ANTES de tocar no filesystem.
    case "$destino" in
      ""|/*|../*|*/../*|*/..|"..") echo "  DESTINO INVALIDO: [$destino]"; ruins=$((ruins+1)); continue ;;
    esac
    case "$origem" in
      ""|/*|../*|*/../*|*/..|"..") echo "  ORIGEM INVALIDA: [$origem]"; ruins=$((ruins+1)); continue ;;
    esac
    # 2. confinamento efetivo. A checagem de forma sozinha nao cobre symlink no meio do
    #    caminho; `realpath -m` resolve e a comparacao e sobre o caminho REAL.
    confinado "$OPT/$(destino_managed "$destino")" "$OPT" \
      || { echo "  DESTINO ESCAPA DE $OPT: [$destino]"; ruins=$((ruins+1)); continue; }
    confinado "$REPO/$origem" "$REPO" \
      || { echo "  ORIGEM ESCAPA DE $REPO: [$origem]"; ruins=$((ruins+1)); continue; }
    [ -e "$REPO/$origem" ] || { echo "  ORIGEM INEXISTENTE: [$origem]"; ruins=$((ruins+1)); }
  done < <(tipos_politica)
  [ "$ruins" -eq 0 ]
}
# =============================================================================================

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
  #
  # A MARCA `_managed_by` E CONSULTADA AQUI, e nao so no ramo de backup. Antes, o comentario
  # acima ja prometia isto e o codigo nao cumpria: `--revert` apagava QUALQUER
  # `managed-settings.json`, inclusive uma politica corporativa de outra ferramenta - que pode
  # conter `permissions.deny` - sem backup e sem aviso, e sob `sudo`. Promessa em comentario
  # que o codigo nao entrega e o defeito central deste repositorio, aqui no caminho destrutivo.
  if [ -f "$SETTINGS" ] && ! jq -e '._managed_by == "evidence-gate"' "$SETTINGS" >/dev/null 2>&1; then
    echo "ERRO: '$SETTINGS' NAO foi escrito por este instalador (falta a marca _managed_by)." >&2
    echo "      Nada foi removido. Se a intencao e descartar essa politica, remova-a a mao" >&2
    echo "      depois de ler o conteudo - este script nao apaga o que nao criou." >&2
    exit 1
  fi
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
  # Tambem valida o manifesto: `--verify` monta caminhos a partir dele para hashear, e um
  # destino hostil faria a conformidade LER fora de $OPT. Nao escreve, mas "conforme" sobre
  # arquivo de outro lugar seria conformidade falsa.
  if ! valida_manifesto; then
    echo "ERRO: manifesto rejeitado - caminho fora dos limites. Conformidade NAO VERIFICADA." >&2
    exit 1
  fi
  out="$(conformidade_managed)"; printf '%s\n' "$out" | grep -v '^RESUMO' || true
  read -r _ n div dono grav <<<"$(printf '%s\n' "$out" | grep '^RESUMO')"
  # HONESTIDADE DE MODO. As colunas de dono e de gravabilidade so sao AVALIADAS quando o
  # prefixo e a raiz real; sob prefixo de ensaio o laco nem entra nesse ramo. Imprimir "0
  # gravaveis pelo ator" ali era pos-condicao vacuamente verdadeira - a checagem nao executou -
  # e a suite lia esse veredito como aprovacao da garantia CENTRAL da fase 2.
  if [ "$REAL" -eq 1 ]; then
    printf 'managed: %s componentes | %s divergentes | %s com dono errado | %s gravaveis pelo ator\n' \
           "$n" "$div" "$dono" "$grav"
  else
    printf 'managed: %s componentes | %s divergentes | dono=NAO VERIFICADO gravabilidade=NAO VERIFICADO (prefixo de ensaio)\n' \
           "$n" "$div"
  fi
  if [ -f "$SETTINGS" ]; then
    printf 'allowManagedHooksOnly=%s\n' "$(jq -r '.allowManagedHooksOnly // false' "$SETTINGS" 2>/dev/null)"
  else
    echo "managed-settings.json AUSENTE"; exit 1
  fi
  [ "${n:-0}" -gt 0 ] || { echo "ESTADO: conjunto VAZIO - nada a verificar, nao e conformidade" >&2; exit 1; }
  [ "$div" -eq 0 ] && [ "$dono" -eq 0 ] && [ "$grav" -eq 0 ] || exit 1
  if [ "$REAL" -eq 1 ]; then
    echo "ESTADO: politica fora do espaco de escrita do ator"
  else
    # A frase acima e a AFIRMACAO CENTRAL da fase 2, e sob prefixo de ensaio ela nao foi
    # medida: posse e gravabilidade so sao avaliadas na raiz real. Imprimi-la aqui seria
    # publicar a garantia a partir do modo em que ela e inverificavel.
    echo "ESTADO: conteudo conforme. A posse por root e a NAO-gravabilidade pelo ator sao"
    echo "        NAO VERIFICADAS neste modo - exigem a raiz real e execucao como root."
  fi
  exit 0
fi

# ---------------------------------------------------------------- deploy / enforce
# PORTAO ZERO: valida TODO o manifesto antes da primeira escrita. Nao ha "aborta no meio":
# um manifesto parcialmente aplicado como root e pior do que nenhum.
if ! valida_manifesto; then
  echo "ERRO: manifesto rejeitado - caminho fora dos limites. NADA foi escrito." >&2
  echo "      O manifesto e conteudo de repositorio; num contexto root ele e entrada nao" >&2
  echo "      confiavel. Regenere com 'bash install/manifest.sh' e inspecione o diff." >&2
  exit 1
fi
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
# `n` ENTRA NO PORTAO. Sem isto o portao contava DIVERGENCIA e nunca POPULACAO: com o conjunto
# de politica VAZIO, o laco de copia nao copia nada, a conformidade nao itera nada, e
# `0 divergentes` era lido como aprovacao - gravando `allowManagedHooksOnly: true` apontando
# para 14 caminhos inexistentes. Isto e o mecanismo inteiro de hooks desligado com aparencia de
# ligado, que e exatamente a armadilha que este arquivo diz tratar.
# Medido: `tr '\t' ' ' < manifest.lock` (qualquer normalizacao de whitespace, filtro de git ou
# renome de coluna) produz 0 linhas e o --enforce aprovava. MG6 nao pegava: ele sabota UMA
# entrada (div=1), nao esvazia o conjunto. Ausencia de divergencia num conjunto vazio e
# vacuamente verdadeira - a mesma forma logica que este repositorio persegue desde o ADR 0022.
ESPERADOS="$(tipos_politica | wc -l | tr -d ' ')"
if [ "${n:-0}" -eq 0 ] || [ "$n" -ne "$ESPERADOS" ]; then
  echo "ERRO: conjunto de politica VAZIO ou incompleto (n=$n, esperado=$ESPERADOS)." >&2
  echo "      Nada foi escrito e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      Um manifesto que nao produz componentes nao e um deploy conforme: e um deploy" >&2
  echo "      inexistente. Regenere com 'bash install/manifest.sh'." >&2
  exit 1
fi
if [ "$div" -ne 0 ] || [ "$dono" -ne 0 ] || [ "$grav" -ne 0 ]; then
  # MENSAGEM CORRIGIDA (auditoria de 2026-08-04). A versao anterior afirmava "o estado anterior
  # permanece intacto", e isso foi MEDIDO COMO FALSO: quando esta linha era alcancada, os
  # arquivos ja haviam sido copiados. O portao protege a POLITICA, nao a arvore em $OPT - e uma
  # mensagem de erro que promete mais do que o codigo entrega e a mesma classe de defeito que
  # este repositorio persegue, agravada por aparecer justamente no caminho de falha.
  echo "ERRO: deploy incompleto." >&2
  echo "      A POLITICA nao foi escrita e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      ATENCAO: arquivos sob $OPT PODEM ter sido escritos antes desta checagem." >&2
  echo "      Para limpar: bash install/apply-managed.sh --revert" >&2
  exit 1
fi

# --- managed-settings.json, a partir da MESMA especificacao que o escopo de usuario ---
ENFORCE=false; [ "$MODO" = "enforce" ] && ENFORCE=true
# base = "$OPT/hooks", nao literal "/opt/...": sob prefixo de ensaio o JSON precisa apontar
# para os arquivos que de fato existem, senao o teste nao pode conferir que o caminho declarado
# corresponde a um hook presente - e essa checagem e justamente a que impede ativar apontando
# para o vazio.
HOOKS_JSON="$(bash install/hooks-spec.sh "$OPT/hooks")" || exit 1

# PORTAO DE POPULACAO CONTRA A FONTE QUE DECLARA O CONSUMO.
#
# O portao anterior era TAUTOLOGICO, e o cabecalho deste arquivo prometia o que ele nao fazia.
# Ele comparava `n` (itens conformes) com `tipos_politica | wc -l` - e `n` vinha do laco que
# itera a MESMA `tipos_politica`. So podia falhar com o conjunto vazio. Medido: removendo UMA
# linha do manifesto (`grep -v` do verify-gate), `--enforce` saia 0, gravava
# `allowManagedHooksOnly: true`, e a politica declarava `bash .../hooks/verify-gate.sh` para um
# arquivo QUE NAO EXISTIA. `--verify` sobre esse estado imprimia `0 divergentes` e
# `conteudo conforme`.
#
# O gatilho e o procedimento NORMAL do repositorio, nao sabotagem: `install/manifest.sh` gera
# por glob de diretorio; renomear ou mover um hook e regenerar produz esse estado.
#
# A politica vem de OUTRA fonte - `install/hooks-spec.sh` - e o produto nunca a confrontava com
# o disco. A propriedade existia apenas no oraculo do teste (MG4), exercitada sobre o manifesto
# real, onde era vacuamente verdadeira: a garantia morava no TESTE e nao no ARTEFATO, que e a
# inversao que este repositorio persegue. Agora quem DECLARA o consumo e quem e cobrado.
AUSENTES=0
while IFS= read -r _cmd; do
  _p="${_cmd#bash }"
  [ -f "$_p" ] || { echo "  HOOK DECLARADO NA POLITICA E AUSENTE NO DISCO: $_p" >&2; AUSENTES=$((AUSENTES+1)); }
done < <(printf '%s' "$HOOKS_JSON" | jq -r '[..|objects|select(has("command"))|.command]|unique[]')
if [ "$AUSENTES" -ne 0 ]; then
  echo "ERRO: a politica declara $AUSENTES hook(s) inexistentes em $OPT." >&2
  echo "      Nada foi escrito e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      Politica apontando para o vazio COM enforcement ligado e o mecanismo inteiro" >&2
  echo "      desligado com aparencia de ligado. Regenere o manifesto e reinstale." >&2
  exit 1
fi

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
