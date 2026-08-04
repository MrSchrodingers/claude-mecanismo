#!/usr/bin/env bash
# FRONTEIRA EXTERNA - o contexto exigido pelo required check e UNICO por SHA.
#
# POR QUE ESTA SUITE EXISTE - defeito MEDIDO, nao inferido (2026-08-04).
#
# O workflow chamava-se `verify`, disparava em `push` e em `pull_request`, e tinha um unico job
# `verify`. Sobre o head do PR #4:
#
#   $ gh api repos/MrSchrodingers/evidence-gate/commits/ef307bf.../check-runs \
#       --jq '.total_count, (.check_runs[] | "\(.name) | \(.conclusion) | id=\(.id)")'
#   2
#   verify | success | id=92057531104
#   verify | success | id=92057522494
#
# DOIS check-runs homonimos sobre o MESMO SHA. Um required status check e identificado por NOME.
# Qual dos dois a regra avalia quando eles DIVERGEM nao foi localizado na doc primaria - a
# limitacao esta registrada em C-016, e medi-la exigiria empurrar um commit vermelho de proposito
# para o branch protegido. A fronteira que esta arquitetura inteira existe para tornar inequivoca
# terminava, ela propria, ambigua.
#
# A propriedade exigida NAO e:
#     |{check-runs chamados `verify` para SHA}| >= 1
# E:
#     |{check-runs com o nome do contexto exigido para SHA}| = 1
#
# O QUE ESTA SUITE VERIFICA, E O QUE NAO VERIFICA
# ----------------------------------------------
# VERIFICA (estatico, sobre os arquivos do repositorio):
#   - exatamente um job responde pelos eventos que decidem merge;
#   - o nome desse job nao colide com o nome de nenhum outro job de nenhum workflow;
#   - os passos do job exigido e do job de push sao IDENTICOS (o preco de ter dois arquivos);
#   - o contexto que o cabecalho manda configurar no ruleset e o nome que o job realmente produz.
#
# NAO VERIFICA: que o GitHub nomeie o check-run com o nome do job. Isso e comportamento de
# plataforma, nao deste repositorio. A evidencia disponivel e a medicao acima - job `verify` sem
# `name:` explicito produziu check-run `verify` - e ela SUSTENTA a premissa sem prova-la. Por
# isso os jobs abaixo declaram `name:` explicito e igual ao job id: as duas rotas possiveis de
# nomeacao levam ao mesmo string, e a premissa deixa de decidir o resultado.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# Parametrizavel SO para a mutacao (tests/mutation/fronteira.sh), que precisa alimentar o
# detector com um diretorio de workflows mutado. Em uso normal e o diretorio real.
WF="${FRONTEIRA_WF_DIR:-.github/workflows}"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO, nao variacao de ambiente: sem parser YAML nao ha como decidir se a
# fronteira e unica, e "nao reprovou" seria indistinguivel de "nao foi verificado". Mesmo
# tratamento que tests/unit/claims.sh da a pyyaml: exit 2.
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "NAO VERIFICADO: pyyaml ausente - a fronteira externa nao pode ser validada aqui." >&2
  echo "Instale a versao pinada (ver .github/workflows/verify-pr.yml)." >&2
  exit 2
fi

# O analisador imprime um relatorio de linhas "campo<TAB>valor" e o shell decide. Manter a
# decisao no shell (e nao dentro do python) mantem cada caso legivel e atribuivel.
REL="$(python3 - "$WF" <<'PY'
import glob, os, sys, yaml

wfdir = sys.argv[1]
# Eventos que DECIDEM merge. `merge_group` entra: se a fila de merge nao avaliar o contexto
# exigido, nada sai dela. `push` NAO entra - push nao decide merge, e por isso nao pode
# carregar o nome exigido.
DECISORIOS = {"pull_request", "pull_request_target", "merge_group"}

jobs = []   # (arquivo, job_id, nome_do_contexto, eventos, passos)
for caminho in sorted(glob.glob(os.path.join(wfdir, "*.yml")) +
                      glob.glob(os.path.join(wfdir, "*.yaml"))):
    with open(caminho, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        continue
    # PyYAML resolve a chave `on:` para o booleano True (YAML 1.1). Ler as duas formas nao e
    # tolerancia: e o unico jeito de nao medir vazio e chamar isso de aprovacao.
    gat = doc.get("on", doc.get(True)) or {}
    eventos = set(gat.keys()) if isinstance(gat, dict) else (
        set(gat) if isinstance(gat, list) else {str(gat)})
    for jid, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        # O contexto e o `name:` do job; sem ele, o job id.
        jobs.append((os.path.basename(caminho), jid, str(job.get("name", jid)),
                     eventos, job.get("steps")))

decisorios = [j for j in jobs if j[3] & DECISORIOS]
print("jobs_total\t%d" % len(jobs))
print("jobs_decisorios\t%d" % len(decisorios))
print("contextos_decisorios\t%s" % ",".join(sorted({j[2] for j in decisorios})))

# Colisao: mesmo nome de contexto produzido por mais de um job.
from collections import Counter
colisoes = sorted(n for n, c in Counter(j[2] for j in jobs).items() if c > 1)
print("colisoes\t%s" % (",".join(colisoes) if colisoes else "-"))

# `push` que NAO decide merge nao pode compartilhar contexto com quem decide.
nomes_dec = {j[2] for j in decisorios}
push = [j for j in jobs if "push" in j[3] and not (j[3] & DECISORIOS)]
print("jobs_push\t%d" % len(push))
print("push_colide_com_decisorio\t%s" % ("sim" if {j[2] for j in push} & nomes_dec else "nao"))

# ANTI-DRIFT: dois arquivos so se justificam se verificarem a MESMA coisa. Compara os passos
# do job decisorio com os do job de push. Serializar em YAML canonico compara ESTRUTURA, nao
# formatacao - comentario e indentacao podem diferir, a verificacao nao pode.
if len(decisorios) == 1 and len(push) == 1:
    a = yaml.safe_dump(decisorios[0][4], sort_keys=False)
    b = yaml.safe_dump(push[0][4], sort_keys=False)
    print("passos_identicos\t%s" % ("sim" if a == b else "nao"))
    print("n_passos\t%d" % len(decisorios[0][4] or []))
else:
    print("passos_identicos\tindeterminado")
    print("n_passos\t0")

# O contexto que o cabecalho manda configurar no ruleset.
declarado = "-"
for caminho in sorted(glob.glob(os.path.join(wfdir, "*.yml")) +
                      glob.glob(os.path.join(wfdir, "*.yaml"))):
    with open(caminho, encoding="utf-8") as fh:
        for linha in fh:
            if not linha.lstrip().startswith("#"):
                break   # so o cabecalho; nao varrer o corpo
            if "required status check" in linha and '"' in linha:
                declarado = linha.split('"')[1]
print("contexto_declarado\t%s" % declarado)
PY
)" || { echo "FAIL: o analisador da fronteira nao executou"; exit 1; }

campo(){ printf '%s\n' "$REL" | awk -F'\t' -v k="$1" '$1==k{print $2}'; }

echo "== FE1. exatamente UM job responde pelos eventos que decidem merge =="
# Com dois (o defeito medido), o required check por nome nao discrimina qual avaliar.
chk "um unico job decisorio" "$(campo jobs_decisorios)" "1"

echo "== FE2. nenhum contexto e produzido por mais de um job =="
# Generalizacao do defeito: nao basta separar ESTES dois; nenhum par pode colidir.
chk "sem nome de job duplicado entre workflows" "$(campo colisoes)" "-"
chk "o job de push nao usa o contexto de quem decide merge" \
    "$(campo push_colide_com_decisorio)" "nao"

echo "== FE3. os dois workflows verificam a MESMA coisa =="
# O preco de ter dois arquivos e a chance de divergirem. Este caso e o pagamento.
chk "passos do job decisorio e do de push sao identicos" "$(campo passos_identicos)" "sim"
# ANTIVACUIDADE: com `steps` vazio ou ilegivel, "identicos" seria verdadeiro e nada teria
# sido comparado. O caso so vale se houve substancia a comparar.
NPASSOS="$(campo n_passos)"
chk "e havia passos a comparar (nao vacuo)" "$([ "${NPASSOS:-0}" -ge 10 ] && echo sim || echo nao)" "sim"

echo "== FE4. o ruleset que o cabecalho manda configurar e o contexto que o job produz =="
# DRIFT DOC/MECANISMO: o cabecalho anterior mandava exigir "verify" e o job produzia "verify" -
# casava, e ainda assim estava errado, porque DOIS jobs produziam esse nome. Casar o texto com o
# mecanismo so vale junto com FE1 e FE2; isolado, seria selo.
chk "contexto declarado no cabecalho == contexto decisorio" \
    "$(campo contexto_declarado)" "$(campo contextos_decisorios)"

echo
printf '================ PASS=%s  FAIL=%s ================\n' "$P" "$F"
if [ "$F" -eq 0 ]; then echo "fronteira externa verde ($P/$P)"; exit 0
else echo "fronteira externa VERMELHA ($F falhas)"; exit 1; fi
