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

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=23
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "raiz de confianca verde ($P/$EXPECTED)" || echo "raiz de confianca VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
