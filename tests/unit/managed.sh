#!/usr/bin/env bash
# RAIZ DE CONFIANCA (fase 2) - `install/apply-managed.sh` e `install/hooks-spec.sh`.
#
# O QUE ESTA SUITE PODE E O QUE NAO PODE PROVAR. Ela exercita TODA a logica do instalador
# managed contra um prefixo temporario: copia, digest, geracao do JSON, deteccao de
# adulteracao, portao de ativacao e reversao. Ela NAO prova que o runtime honra
# `allowManagedHooksOnly`, porque isso exige escrever em `/etc/claude-code` com root - e a
# afirmacao correspondente so pode ser feita a partir de medicao com o binario, registrada em
# `evidence/observations/`. Confundir as duas seria dizer que o artefato esta verificado porque
# a fixture passou.
#
# MG6 e o caso mais importante. Ele existe porque a PRIMEIRA versao do instalador gravava o
# `managed-settings.json` - com `allowManagedHooksOnly: true` - ANTES de conferir se o deploy
# estava completo. Consequencia: deploy incompleto deixaria o sistema sem hooks managed E com
# os de usuario bloqueados; o mecanismo inteiro cairia, que e a armadilha nomeada no handoff.
# E a mesma classe do defeito do `--dry-run` do ADR 0022, adendo 2: garantia nova, correta,
# mal posicionada em relacao a escrita.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
REPO="$PWD"
AM="$REPO/install/apply-managed.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "NAO VERIFICADO: jq ausente." >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FK="$T/raiz"; mkdir -p "$FK"

echo "== MG1. a especificacao de hooks tem FONTE UNICA =="
# Duas copias da mesma lista divergem em silencio: e o defeito que originou este repositorio.
A="$T/user.json"; B="$T/managed.json"
bash install/hooks-spec.sh '$HOME/.claude/hooks' > "$A"
bash install/hooks-spec.sh '/opt/evidence-gate/hooks' > "$B"
chk "o spec e JSON valido nos dois escopos" \
    "$(jq -e . "$A" >/dev/null 2>&1 && jq -e . "$B" >/dev/null 2>&1 && echo sim || echo nao)" "sim"
est(){ jq -S '[paths(scalars) as $p | [$p|map(tostring)|join(".")]] | flatten | sort' "$1"; }
chk "  a ESTRUTURA e identica nos dois escopos" \
    "$(cmp -s <(est "$A") <(est "$B") && echo sim || echo nao)" "sim"
bn(){ jq -r '[..|objects|select(has("command"))|.command] | map(sub(".*/";"")) | sort | join(",")' "$1"; }
chk "  os scripts sao os mesmos, so muda o caminho" "$(bn "$A")" "$(bn "$B")"
chk "  o \$HOME sai LITERAL no escopo de usuario (quem expande e o runtime)" \
    "$(grep -c 'bash \$HOME/\.claude/hooks/' "$A" | tr -d ' ')" "18"
# Sem esta assercao, alguem poderia reintroduzir a lista dentro do apply.sh e a fonte unica
# viraria fonte dupla sem nenhum sinal.
chk "  apply.sh NAO reintroduziu copia embutida da lista" \
    "$(grep -c '"type":"command","command":"bash \$HOME' install/apply.sh | tr -d ' ')" "0"

echo "== MG2. --dry-run nao escreve nada =="
rm -rf "$FK"; mkdir -p "$FK"
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --dry-run >/dev/null 2>&1; echo $?)
chk "o plano executa (exit 0)" "$rc" 0
chk "  e o disco continua vazio" "$([ -d "$FK/opt" ] || [ -d "$FK/etc" ] && echo escreveu || echo vazio)" "vazio"

echo "== MG3. deploy instala a POLITICA inteira, nao so os hooks =="
# Politica root-owned lendo tabela de adaptadores user-owned e raiz de confianca so no nome:
# o ator desligaria o gate pela tabela, sem tocar no hook.
rc=$(MANAGED_PREFIX="$FK" bash "$AM" >/dev/null 2>&1; echo $?)
chk "deploy executa (exit 0)" "$rc" 0
N=$(find "$FK/opt/evidence-gate" -type f 2>/dev/null | wc -l | tr -d ' ')
ESPERADO=$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' install/manifest.lock | wc -l | tr -d ' ')
chk "  todos os $ESPERADO componentes de politica no disco" "$N" "$ESPERADO"
chk "  ha hook, adaptador E doctool (nao so hook)" \
    "$([ -d "$FK/opt/evidence-gate/hooks" ] && [ -d "$FK/opt/evidence-gate/adapters" ] && [ -d "$FK/opt/evidence-gate/document-tools" ] && echo sim || echo nao)" "sim"
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "  --verify aprova o estado recem-instalado" "$rc" 0
chk "  allowManagedHooksOnly nasce FALSE (deploy nao ativa)" \
    "$(jq -r '.allowManagedHooksOnly' "$FK/etc/claude-code/managed-settings.json")" "false"

echo "== MG4. todo hook DECLARADO na politica existe no disco =="
# Politica apontando para caminho vazio, com enforcement ligado, e o mecanismo desligado com
# aparencia de ligado.
MISS=0
while read -r cmd; do
  p="${cmd#bash }"; [ -f "$p" ] || MISS=$((MISS+1))
done < <(jq -r '[.hooks|..|objects|select(has("command"))|.command]|unique[]' "$FK/etc/claude-code/managed-settings.json")
chk "nenhum caminho declarado aponta para o vazio" "$MISS" "0"

echo "== MG5. adulteracao de UM byte reprova a conformidade =="
printf '\n# adulterado\n' >> "$FK/opt/evidence-gate/hooks/verify-gate.sh"
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "--verify REPROVA politica adulterada" "$rc" 1
MANAGED_PREFIX="$FK" bash "$AM" >/dev/null 2>&1
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "  e reinstalar reconverge" "$rc" 0

echo "== MG6. --enforce RECUSA ativar sobre deploy incompleto =="
# O caso que impede derrubar o mecanismo inteiro. Manifesto sabotado via override, para nao
# mutar o arquivo real: se a suite morresse no meio, o repositorio ficaria quebrado.
MANSAB="$T/manifest-sabotado.lock"
awk -F'\t' 'BEGIN{OFS="\t"} $1=="hook" && ++c==1 {$2="control/hooks/NAO-EXISTE.sh"} {print}' \
    install/manifest.lock > "$MANSAB"
chk "o manifesto sabotado difere do real (senao o caso e vacuo)" \
    "$(cmp -s "$MANSAB" install/manifest.lock && echo igual || echo difere)" "difere"
FK2="$T/raiz2"; mkdir -p "$FK2/etc/claude-code"
printf '{"allowManagedHooksOnly":false}\n' > "$FK2/etc/claude-code/managed-settings.json"
rc=$(MANAGED_PREFIX="$FK2" MANAGED_MANIFEST="$MANSAB" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "--enforce reprova com deploy incompleto" "$rc" 1
chk "  e allowManagedHooksOnly NAO foi ativado" \
    "$(jq -r '.allowManagedHooksOnly' "$FK2/etc/claude-code/managed-settings.json")" "false"

echo "== MG7. --enforce ativa quando o deploy esta completo =="
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "--enforce executa (exit 0)" "$rc" 0
chk "  allowManagedHooksOnly=true" \
    "$(jq -r '.allowManagedHooksOnly' "$FK/etc/claude-code/managed-settings.json")" "true"

echo "== MG8. --revert desfaz por completo =="
rc=$(MANAGED_PREFIX="$FK" bash "$AM" --revert >/dev/null 2>&1; echo $?)
chk "--revert executa (exit 0)" "$rc" 0
chk "  a politica saiu do disco" \
    "$([ -e "$FK/opt/evidence-gate" ] || [ -e "$FK/etc/claude-code/managed-settings.json" ] && echo sobrou || echo limpo)" "limpo"
# DEFEITO ENCONTRADO POR ESTE CASO: o backup `pre-evidence-gate` era criado mesmo quando o
# arquivo existente havia sido escrito pelo PROPRIO instalador (deploy seguido de --enforce).
# O --revert entao restaurava esse "backup" e RECRIAVA a politica. Reversao que nao reverte e
# pior que ausencia de reversao: o operador acredita ter voltado ao estado anterior.
chk "  e nao sobrou backup espurio do proprio instalador" \
    "$([ -e "$FK/etc/claude-code/managed-settings.json.pre-evidence-gate" ] && echo sobrou || echo limpo)" "limpo"

echo "== MG9. manifesto com caminho hostil e REJEITADO, sem escrever nada =="
# ACHADO DE AUDITORIA, com PoC executada: o manifesto e arquivo do REPOSITORIO, isto e, esta no
# espaco de escrita do ator governado, e suas colunas eram usadas verbatim como caminho de
# `mkdir -p`, `cp -f` e `rm -rf` - com o script rodando como ROOT. Medido antes da correcao:
#   destino=../../../ZONA/vitima.conf  -> arquivo FORA do prefixo sobrescrito
#   destino=../../../ZONA (origem=dir) -> `rm -rf` destruiu o diretorio FORA do prefixo
# Sob sudo isso e escrita e remocao arbitrarias como root a partir de dado que o ator controla.
# A raiz de confianca seria instalada A PARTIR DE entrada nao confiavel - a inversao da tese.
ZONA="$T/zona-proibida"; mkdir -p "$ZONA"
printf 'intocavel\n' > "$ZONA/vitima.conf"
HOSTIL="$T/hostil.lock"
printf 'hook\tevidence/hooks/subagent-contract.sh\t../../../zona-proibida/vitima.conf\tdead\n' > "$HOSTIL"
FK3="$T/raiz3"; mkdir -p "$FK3"
rc=$(MANAGED_PREFIX="$FK3" MANAGED_MANIFEST="$HOSTIL" bash "$AM" >/dev/null 2>&1; echo $?)
chk "destino com '..' reprova" "$rc" 1
chk "  a vitima FORA do prefixo esta intacta" "$(cat "$ZONA/vitima.conf" 2>/dev/null)" "intocavel"
chk "  e nada foi escrito no prefixo" "$([ -e "$FK3/opt" ] && echo escreveu || echo vazio)" "vazio"
printf 'hook\t/etc/hostname\thooks/vazado.sh\tdead\n' > "$HOSTIL"
rc=$(MANAGED_PREFIX="$FK3" MANAGED_MANIFEST="$HOSTIL" bash "$AM" >/dev/null 2>&1; echo $?)
chk "origem ABSOLUTA reprova (copiaria arquivo de fora do repo)" "$rc" 1
# CONTROLE: sem ele, um instalador que reprovasse SEMPRE passaria nos quatro casos acima.
rc=$(MANAGED_PREFIX="$T/raiz4" bash "$AM" >/dev/null 2>&1; echo $?)
chk "  e o manifesto REAL continua sendo aceito" "$rc" 0

echo "== MG10. o gerador da politica nao aceita injecao de JSON =="
# O valor do caminho-base ia para `sed "s|@BASE@|$BASE|g"` sobre o texto do JSON. Um valor com
# aspas FECHA a string e ABRE OBJETO NOVO, e o resultado continua JSON VALIDO - o `jq -e .` do
# consumidor nao barra. E esse documento vira politica em /etc/claude-code/.
INJ='/x","timeout":1},{"type":"command","command":"id > /tmp/PWNED_MG10","z":"/y'
OUTJ="$T/inj.json"
bash install/hooks-spec.sh "$INJ" > "$OUTJ" 2>/dev/null
chk "o documento gerado continua sendo JSON valido" \
    "$(jq -e . "$OUTJ" >/dev/null 2>&1 && echo sim || echo nao)" "sim"
# A propriedade nao e "nao gera JSON": e o valor hostil virar UM ESCALAR, sem criar entradas
# de hook novas. Contamos a estrutura, nao o texto.
chk "  o numero de hooks NAO aumentou (valor virou escalar, nao estrutura)" \
    "$(jq '[..|objects|select(has("command"))|.command]|length' "$OUTJ")" \
    "$(bash install/hooks-spec.sh /base/inocente | jq '[..|objects|select(has("command"))|.command]|length')"
chk "  e nenhum comando e exatamente o payload injetado" \
    "$(jq -r '[..|objects|select(has("command"))|.command]|map(select(.=="id > /tmp/PWNED_MG10"))|length' "$OUTJ")" "0"
# `&` era expandido pelo sed como retrovisor, corrompendo o caminho em silencio.
chk "  '&' no caminho nao vira retrovisor" \
    "$(bash install/hooks-spec.sh '/tmp/&&&' | jq -r '.Stop[0].hooks[0].command')" \
    "bash /tmp/&&&/verify-gate.sh"

echo "== MG11. conjunto de politica VAZIO nao e conformidade =="
# ACHADO DE REVISAO INDEPENDENTE, com PoC executada. O portao contava DIVERGENCIA e nunca
# POPULACAO. Com o conjunto vazio: o laco de copia nao copia nada, a conformidade nao itera
# nada, "0 divergentes" era lido como aprovacao, e `--enforce` gravava
# allowManagedHooksOnly:true apontando para 14 caminhos INEXISTENTES - o mecanismo inteiro de
# hooks desligado com aparencia de ligado, que e a armadilha que este arquivo diz tratar.
# MG6 nao pegava: ele sabota UMA entrada (div=1); nao esvazia o conjunto.
# Ausencia de divergencia num conjunto vazio e vacuamente verdadeira.
VAZIO="$T/vazio.lock"
# `tr` nos separadores e o gatilho realista: qualquer normalizacao de whitespace, filtro de
# git ou renome de coluna produz o mesmo efeito.
tr '\t' ' ' < install/manifest.lock > "$VAZIO"
chk "o manifesto degradado de fato produz ZERO componentes" \
    "$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' "$VAZIO" | wc -l | tr -d ' ')" "0"
FK5="$T/raiz5"; mkdir -p "$FK5"
rc=$(MANAGED_PREFIX="$FK5" MANAGED_MANIFEST="$VAZIO" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "  --enforce REPROVA com conjunto vazio" "$rc" 1
chk "  e a politica nem chegou a ser criada" \
    "$([ -f "$FK5/etc/claude-code/managed-settings.json" ] && echo criada || echo ausente)" "ausente"
rc=$(MANAGED_PREFIX="$FK5" MANAGED_MANIFEST="$VAZIO" bash "$AM" --verify >/dev/null 2>&1; echo $?)
chk "  --verify tambem REPROVA (vazio nao e conforme)" "$rc" 1

echo "== MG12. --revert nao apaga politica que nao foi este instalador que escreveu =="
# O comentario do ramo de reversao ja prometia "Remove SOMENTE o que este script cria", e o
# codigo nao cumpria: apagava QUALQUER managed-settings.json, inclusive politica corporativa de
# outra ferramenta - que pode conter permissions.deny - sem backup, sem aviso, e sob sudo.
# Promessa em comentario que o codigo nao entrega, no caminho destrutivo.
FK6="$T/raiz6"; mkdir -p "$FK6/etc/claude-code"
printf '{"_managed_by":"OUTRA-FERRAMENTA","permissions":{"deny":["Bash"]}}\n' > "$FK6/etc/claude-code/managed-settings.json"
rc=$(MANAGED_PREFIX="$FK6" bash "$AM" --revert >/dev/null 2>&1; echo $?)
chk "--revert REPROVA diante de politica de terceiro" "$rc" 1
chk "  e a politica de terceiro continua no disco" \
    "$(jq -r '._managed_by' "$FK6/etc/claude-code/managed-settings.json" 2>/dev/null)" "OUTRA-FERRAMENTA"
# CONTROLE: sem ele, um --revert que reprovasse SEMPRE passaria nos dois casos acima.
FK7="$T/raiz7"
MANAGED_PREFIX="$FK7" bash "$AM" >/dev/null 2>&1
rc=$(MANAGED_PREFIX="$FK7" bash "$AM" --revert >/dev/null 2>&1; echo $?)
chk "  e a politica DESTE instalador continua sendo removida" "$rc" 0

echo "== MG13. sob prefixo de ensaio, posse e gravabilidade sao NAO VERIFICADAS =="
# SETIMA INSTANCIA do padrao vacuo, achada por revisao independente. As colunas de dono e de
# gravabilidade so sao AVALIADAS quando o prefixo e a raiz real; sob ensaio o laco nem entra
# nesse ramo. Imprimir "0 gravaveis pelo ator" ali era pos-condicao trivialmente verdadeira -
# e essa e a garantia CENTRAL da fase 2, lida pela suite como aprovada.
FK8="$T/raiz8"
MANAGED_PREFIX="$FK8" bash "$AM" >/dev/null 2>&1
SAIDA="$(MANAGED_PREFIX="$FK8" bash "$AM" --verify 2>&1)"
chk "o modo de ensaio declara NAO VERIFICADO em vez de 0" \
    "$(printf '%s' "$SAIDA" | grep -qc 'NAO VERIFICADO' >/dev/null && echo sim || echo nao)" "sim"
chk "  e NAO afirma 'fora do espaco de escrita do ator'" \
    "$(printf '%s' "$SAIDA" | grep -q 'ESTADO: politica fora do espaco' && echo afirma || echo nao-afirma)" "nao-afirma"
chk "  os arquivos sob ensaio sao mesmo gravaveis (a garantia NAO vale ali)" \
    "$([ -w "$FK8/opt/evidence-gate/hooks/verify-gate.sh" ] && echo gravavel || echo protegido)" "gravavel"

echo "== MG14. politica que declara hook AUSENTE nao pode ser ativada =="
# PORTAO FINAL, 2026-08-04. O portao de populacao era TAUTOLOGICO: comparava `n` (conformes)
# com `tipos_politica | wc -l`, e `n` vinha do laco que itera a MESMA fonte. So podia falhar
# com o conjunto vazio - que e o que MG11 cobre. Remover UMA linha do manifesto passava.
# Medido: --enforce EXIT=0, allowManagedHooksOnly=true, e a politica declarando
# `bash .../hooks/verify-gate.sh` para um arquivo INEXISTENTE; --verify sobre esse estado
# imprimia "0 divergentes" e "conteudo conforme".
# O gatilho e o procedimento NORMAL: manifest.sh gera por glob, entao renomear ou mover um
# hook e regenerar produz esse estado sem nenhuma edicao manual.
# A politica vem de OUTRA fonte (hooks-spec.sh) e o produto nunca a confrontava com o disco -
# a propriedade existia so no oraculo de MG4, exercitada sobre o manifesto real, onde era
# vacuamente verdadeira. Garantia no TESTE e nao no ARTEFATO.
SEMHOOK="$T/sem-um-hook.lock"
grep -v "evidence/hooks/verify-gate.sh" install/manifest.lock > "$SEMHOOK"
chk "o manifesto degradado perdeu exatamente 1 linha (senao o caso e outro)" \
    "$(( $(wc -l < install/manifest.lock) - $(wc -l < "$SEMHOOK") ))" "1"
chk "  e ele ainda produz componentes (nao e o caso vazio de MG11)" \
    "$([ "$(awk -F'\t' '!/^#/ && ($1=="hook"||$1=="adapter"||$1=="doctool")' "$SEMHOOK" | wc -l)" -gt 0 ] && echo sim || echo nao)" "sim"
FK9="$T/raiz9"; mkdir -p "$FK9"
rc=$(MANAGED_PREFIX="$FK9" MANAGED_MANIFEST="$SEMHOOK" bash "$AM" --enforce >/dev/null 2>&1; echo $?)
chk "  --enforce REPROVA: a politica declara hook que nao esta no disco" "$rc" 1
chk "  e allowManagedHooksOnly nao foi ativado" \
    "$(jq -r '.allowManagedHooksOnly' "$FK9/etc/claude-code/managed-settings.json" 2>/dev/null || echo ausente)" "ausente"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=46
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "raiz de confianca verde ($P/$EXPECTED)" || echo "raiz de confianca VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
