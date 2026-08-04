#!/usr/bin/env bash
# CLAIM LEDGER - a suite do validador (evidence/validate-claims.py).
#
# O caso L1 sozinho nao vale nada: um validador que aprovasse QUALQUER coisa passaria nele. O
# valor desta suite esta nos casos NEGATIVOS - L2 a L8 - que exigem reprovacao. Foi precisamente
# a ausencia de negativo que deixou o oraculo da ancora do contrato de subagente sem poder de
# decisao medido por versoes inteiras (ver docs/adr/0023).
#
# L9 e L10 cobrem as duas formas de o validador deixar de medir sem reprovar:
#   L9  - dependencia de ORACULO ausente (pyyaml) -> exit 2, NAO VERIFICADO;
#   L10 - a EXTRACAO do inventario quebra e devolve vazio. Sem a autochecagem isso reprovaria
#         tudo (falso vermelho) ou, com regex frouxa demais, aprovaria tudo (falso verde).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
V="$PWD/evidence/validate-claims.py"
REPO="$PWD"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO: sem pyyaml o validador nao decide nada, e "nao reprovou" seria
# indistinguivel de "nao foi verificado". Reprova a suite em vez de virar SKIP silencioso.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "NAO VERIFICADO: pyyaml ausente - o validador sob teste nao pode operar." >&2
  exit 2
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SHA="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo 0000000)"

# Molde de claim VALIDA. Cada caso negativo altera UM campo, para que a reprovacao seja
# atribuivel aquele campo e nao a um documento genericamente malformado.
molde(){ cat <<EOF
claim_id: $1
claim: "alegacao de teste"
type: empirical-invariant
scope:
  commit: "${3:-$SHA}"
  platforms: [local-linux]
evidence:
  regression: [${2:-G1}]
  ci_run: "http://exemplo.invalido"
warrant: "molde de teste"
limitations: ["fixture"]
status: supported-in-tested-domain
EOF
}
# roda o validador sobre um diretorio de claims descartavel; ecoa so o exit code
val(){ python3 "$V" "$REPO" "$1" >/dev/null 2>&1; echo $?; }

echo "== L1. o ledger REAL do repositorio e valido =="
chk "evidence/claims/ valida" "$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)" 0

echo "== L2. citar regressao INEXISTENTE reprova (a regra central) =="
D="$T/l2"; mkdir -p "$D"; molde C-001 G999 > "$D/C-001.yaml"
chk "regressao G999 nao existe em tests/ -> reprova" "$(val "$D")" 1
D="$T/l2b"; mkdir -p "$D"; molde C-001 G1 > "$D/C-001.yaml"
chk "  e o MESMO molde com G1 (que existe) passa" "$(val "$D")" 0

echo "== L3. citar mutante INEXISTENTE reprova =="
# A PRIMEIRA VERSAO DESTE CASO PASSOU PELO MOTIVO ERRADO. O fixture era montado concatenando
# uma linha ao molde, o que produzia YAML INVALIDO; o validador reprovava no parser e o caso
# ficava verde sem nunca exercitar a resolucao de mutante. Verde por motivo errado e a mesma
# familia do verde vacuo, e so apareceu porque o traceback do parser vazou para a saida.
# Defesa: o par negativo/positivo abaixo difere em UM identificador. Se o positivo passar e o
# negativo reprovar, a diferenca so pode ter vindo da resolucao.
mut_fixture(){ # $1=destino  $2=id de mutante
python3 - "$1" "$2" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"alegacao de teste","type":"empirical-invariant",
     "scope":{"commit":sys.argv[3],"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],"mutants":[sys.argv[2]],"ci_run":"http://exemplo.invalido"},
     "warrant":"molde de teste","limitations":["fixture"],
     "status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
}
D="$T/l3"; mkdir -p "$D"; mut_fixture "$D/C-001.yaml" M999
chk "o fixture e YAML VALIDO (senao o caso mediria o parser)" \
    "$(python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('sim')" "$D/C-001.yaml" 2>/dev/null || echo nao)" "sim"
chk "  mutante M999 nao existe -> reprova" "$(val "$D")" 1
D="$T/l3b"; mkdir -p "$D"; mut_fixture "$D/C-001.yaml" M1
chk "  o MESMO fixture com M1 (que existe) passa" "$(val "$D")" 0

echo "== L4. alegacao SEM nenhuma referencia de evidencia reprova =="
D="$T/l4"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"sem lastro","type":"empirical-invariant",
     "scope":{"commit":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"ci_run":"http://exemplo.invalido"},
     "warrant":"nenhum","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "sem regression, mutants nem observation -> reprova" "$(val "$D")" 1

echo "== L5. scope.commit inexistente reprova =="
D="$T/l5"; mkdir -p "$D"; molde C-001 G1 "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" > "$D/C-001.yaml"
chk "commit que nao existe no repo -> reprova" "$(val "$D")" 1
D="$T/l5b"; mkdir -p "$D"; molde C-001 G1 "--upload-pack=touch /tmp/PWN_CLAIMS" > "$D/C-001.yaml"
rm -f /tmp/PWN_CLAIMS
chk "  valor com cara de OPCAO nao chega ao git" "$(val "$D")" 1
chk "  e nao executa nada" "$([ -f /tmp/PWN_CLAIMS ] && echo nao || echo sim)" "sim"

echo "== L6. observation apontando para arquivo inexistente reprova =="
D="$T/l6"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"observacao fantasma","type":"runtime-observation",
     "scope":{"commit":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"observation":{"command":"echo","recorded":"evidence/observations/nao-existe.md"},
                 "ci_run":"http://exemplo.invalido"},
     "warrant":"nenhum","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "recorded aponta para arquivo ausente -> reprova" "$(val "$D")" 1

echo "== L7. claim_id duplicado reprova =="
D="$T/l7"; mkdir -p "$D"; molde C-001 G1 > "$D/C-001.yaml"; molde C-001 G1 > "$D/C-002.yaml"
chk "dois arquivos com o mesmo claim_id -> reprova" "$(val "$D")" 1

echo "== L8. limitations vazio reprova =="
D="$T/l8"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"sem limites","type":"empirical-invariant",
     "scope":{"commit":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],"ci_run":"http://exemplo.invalido"},
     "warrant":"nenhum","limitations":[],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "toda alegacao tem alcance finito -> lista vazia reprova" "$(val "$D")" 1

echo "== L9. pyyaml ausente e NAO VERIFICADO (exit 2), nao aprovacao =="
# Mesma tecnica de S5: um modulo que lanca ImportError precede o real no PYTHONPATH.
SB="$T/sabotagem"; mkdir -p "$SB"; printf 'raise ImportError("indisponivel por fixture")\n' > "$SB/yaml.py"
rc=$(PYTHONPATH="$SB" python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)
chk "sem parser, o validador declara NAO VERIFICADO" "$rc" 2

echo "== L11. observation com caminho ABSOLUTO ou '..' reprova =="
# ACHADO DE AUDITORIA: `os.path.join(raiz, x)` DESCARTA `raiz` quando `x` e absoluto. Medido:
# uma claim cujo unico lastro era `recorded: /etc/passwd` era APROVADA, e o validador imprimia
# "ledger valido: toda evidencia citada existe em tests/" - frase literalmente falsa. O dano
# nao e a travessia em si: e a alegacao passar a ter lastro FORA do repositorio enquanto o
# programa afirma ter resolvido a evidencia contra a suite.
obs_fixture(){ # $1=destino  $2=valor de recorded
python3 - "$1" "$2" "$SHA" <<'PY2'
import sys, yaml
d = {"claim_id":"C-001","claim":"lastro fora do repo","type":"runtime-observation",
     "scope":{"commit":sys.argv[3],"platforms":["local-linux"]},
     "evidence":{"observation":{"command":"echo","recorded":sys.argv[2]},
                 "ci_run":"http://exemplo.invalido"},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY2
}
D="$T/l11"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "/etc/passwd"
chk "recorded absoluto (/etc/passwd) reprova" "$(val "$D")" 1
D="$T/l11b"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "../../../../etc/hostname"
chk "  recorded com '..' reprova" "$(val "$D")" 1
# CONTROLE: sem ele, um validador que reprovasse toda observation passaria nos dois acima.
D="$T/l11c"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "docs/HANDOFF.md"
chk "  e um caminho relativo VALIDO dentro do repo passa" "$(val "$D")" 0

echo "== L10. inventario vazio e NAO VERIFICADO, nao ledger valido =="
# Autochecagem: se o contrato de extracao deixar de casar com tests/, o validador precisa
# gritar. Sem isto ele reprovaria tudo, ou - com regex frouxa - aprovaria tudo.
FAKE="$T/repo-sem-testes"; mkdir -p "$FAKE/tests/unit" "$FAKE/tests/mutation"
rc=$(python3 "$V" "$FAKE" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)
chk "extracao vazia -> exit 2, nunca 0" "$rc" 2

echo "== L12. a evidencia e resolvida contra o SNAPSHOT declarado, nao contra o worktree =="
# PORTAO FINAL, 2026-08-04. `scope.commit` era DECORATIVO: o validador conferia so que o objeto
# git existia, e resolvia a evidencia contra a arvore de trabalho. Medido: as 16 claims
# declaravam um commit em que os mutantes MC6/MC7 e as duas observacoes NAO EXISTIAM, e o
# validador imprimia "toda evidencia citada existe" - verdadeiro sobre o worktree e FALSO sobre
# o escopo que cada claim declara. Alegacao cujo lastro nao existe no snapshot que ela nomeia
# nao esta ancorada: esta datada errado, que e a forma silenciosa de nao estar ancorada.
ANTIGO="$(git -C "$REPO" rev-list --max-parents=1 -n1 HEAD~6 2>/dev/null || git -C "$REPO" rev-parse HEAD~6 2>/dev/null || echo '')"
if [ -z "$ANTIGO" ]; then
  echo "  SKIP  historico curto demais para exercitar a resolucao por snapshot"
else
  D="$T/l12"; mkdir -p "$D"
  # a MESMA claim, mudando SO o snapshot: se o resultado nao mudar, a resolucao ignora o campo.
  cp "$REPO/evidence/claims/C-011.yaml" "$D/C-011.yaml"
  chk "no snapshot corrente a claim resolve" "$(val "$REPO/evidence/claims")" 0
  python3 - "$D/C-011.yaml" "$ANTIGO" <<'PY3'
import sys, yaml
p, sha = sys.argv[1], sys.argv[2]
raw = open(p).read()
head = "\n".join(l for l in raw.split("\n") if l.startswith("#"))
d = yaml.safe_load(raw); d["scope"]["commit"] = sha
open(p, "w").write(head + "\n")
with open(p, "a") as fh:
    yaml.safe_dump(d, fh, allow_unicode=True, sort_keys=False, width=100)
PY3
  chk "  a MESMA claim num snapshot anterior REPROVA (o campo decide)" "$(val "$D")" 1
fi

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=20
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "claim ledger verde ($P/$EXPECTED)" || echo "claim ledger VERMELHO"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
