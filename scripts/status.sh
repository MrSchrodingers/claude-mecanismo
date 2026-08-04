#!/usr/bin/env bash
# Gera docs/status.generated.md a partir do estado EXECUTADO, nunca de numero digitado a mao.
#
# Existe porque o README voltou a divergir do mecanismo: afirmava "28 assercoes" quando a suite
# ja tinha 29. Pequeno operacionalmente, e exatamente a classe que originou este projeto -
# narrativa e artefato em copias separadas que se afastam sem sinal. A correcao nao e corrigir
# o numero: e parar de duplica-lo.
#
# Uso: scripts/status.sh [saida]   (default: docs/status.generated.md)
# Com --check: nao escreve; reprova se o arquivo committado estiver desatualizado.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# LOCK: status.sh executa TODAS as suites; toma o lock uma vez e as filhas herdam.
. "$(dirname "$0")/../tests/lib/lock.sh"
export LC_ALL=C
OUT="docs/status.generated.md"; CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1 || OUT="${1:-$OUT}"

conta(){ bash "$1" 2>&1 | grep -oE "PASS=[0-9]+" | tail -1 | cut -d= -f2; }
TMP="$(mktemp)"
{
  printf '# Estado gerado\n\n'
  printf 'NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.\n'
  printf 'O README referencia este arquivo em vez de duplicar numeros.\n\n'
  printf '## Suites\n\n| Suite | Assercoes | Exit |\n|---|---:|---:|\n'
  # CONTAGEM AMBIENTE-DEPENDENTE nao entra como numero fixo: `reprodutibilidade.sh` exercita um
  # locale por variante disponivel, entao da 8 numa maquina com pt_BR/de_DE e 6 num runner que
  # so tem en_US. Registrar o numero faria este arquivo divergir por ambiente - o mesmo drift
  # que ele existe para impedir. A CI pegou isso na primeira execucao. Para essas suites vale o
  # exit code, que e estavel; a contagem fica marcada como variavel.
  for t in tests/unit/regressao-gate.sh tests/unit/document-tools.sh tests/unit/supply-chain.sh \
           tests/unit/reprodutibilidade.sh tests/unit/concorrencia.sh \
           tests/unit/claims.sh tests/unit/propriedades.sh tests/unit/fronteira-externa.sh \
           tests/unit/managed.sh tests/unit/run.sh; do
    bash "$t" >/dev/null 2>&1; rc=$?
    if grep -q 'EXPECTED=\$((' "$t"; then n="variavel (ambiente)"
    else n="$(conta "$t")"; fi
    printf '| `%s` | %s | %s |\n' "$t" "${n:-?}" "$rc"
  done
  printf '\n## Mutacao\n\n| Alvo | Mutantes | Exit |\n|---|---:|---:|\n'
  mg="$(grep -c '^mutante M' tests/mutation/run.sh)"; bash tests/mutation/run.sh >/dev/null 2>&1
  printf '| gate | %s | %s |\n' "$mg" "$?"
  mc="$(grep -c '^mutante M' tests/mutation/contrato.sh)"; bash tests/mutation/contrato.sh >/dev/null 2>&1
  printf '| contrato de subagente | %s | %s |\n' "$mc" "$?"
  # DERIVADO, nao digitado. Este numero era o literal `1` e ficou errado no instante em que o
  # segundo mutante entrou - a mesma classe de drift que este arquivo inteiro existe para
  # impedir, dentro do proprio gerador de status. `install.sh` nao usa o helper `mutante`, entao
  # a fonte e a constante que o proprio runner cobra de si (EXPECTED_MUTANTS).
  mi="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/install.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/install.sh >/dev/null 2>&1
  printf '| instalador | %s | %s |\n' "${mi:-?}" "$?"
  mf="$(grep -c '^mutante MF' tests/mutation/fronteira.sh)"; bash tests/mutation/fronteira.sh >/dev/null 2>&1
  printf '| fronteira externa | %s | %s |\n' "$mf" "$?"
  printf '\n## Componentes\n\n| Tipo | Qtd |\n|---|---:|\n'
  awk -F'\t' '!/^#/{c[$1]++} END{for(t in c) printf "| %s | %s |\n", t, c[t]}' install/manifest.lock | sort
  printf '| **total** | **%s** |\n' "$(grep -vc '^#' install/manifest.lock)"
  printf '\n## Limites declarados\n\n'
  # PRECISAO CORRIGIDA (auditoria externa, 2026-08-04). Dizia "raiz de confianca nao
  # implementada", e isso era falso por defeito: o instalador managed existe, e root-owned, faz
  # deploy em staging com publicacao apos os portoes, e tem suite propria. O que nao existe e a
  # ATIVACAO e o fechamento da cadeia. Subdeclarar o proprio estado nao e prudencia: e a mesma
  # imprecisao que superdeclarar, com o sinal trocado, e faz o leitor nao saber o que falta.
  printf -- '- politica `governed=user`: os hooks ativos vivem em ~/.claude, gravavel pelo ator.\n'
  printf -- '  O instalador managed (`install/apply-managed.sh`) esta CONSTRUIDO e exercitado contra\n'
  printf -- '  prefixo de ensaio, mas `allowManagedHooksOnly` NAO foi ativado. Duas dependencias da\n'
  printf -- '  cadeia seguem no espaco do ator: o proprio checkout de onde o instalador roda, e\n'
  printf -- '  `EVIDENCE_GATE_REPO`, que o hook managed de SessionStart usa para achar o verificador.\n'
  printf -- '- ambiente auditavel, nao hermetico: `ubuntu-24.04` fixa familia, nao digest\n'
  printf -- '- sem corpus de desfecho: nenhuma afirmacao sobre eficacia de engenharia\n'
  printf -- '- sem auditoria autoralmente independente: a CI e observador ambiental\n'
  printf -- '- sem sandbox: parsers de documento rodam com a autoridade do usuario\n'
  printf -- '- o ruleset IMPOE, mas quem tem admin pode DESATIVA-LO: nao ha bypass dentro da\n'
  printf -- '  regra (medido), e nao que a regra seja irremovivel\n'
  printf '\n## Deixaram de ser limites (medidos em 2026-08-04)\n\n'
  # Limite que continua escrito depois de resolvido e a mesma classe de drift que originou este
  # arquivo: narrativa em copia separada do mecanismo. Some da lista, mas com o rastro de onde
  # a medicao esta - do contrario o leitor nao sabe se foi resolvido ou apagado.
  printf -- '- `CI executa mas NAO impoe`: o ruleset esta ativo com `bypass_actors` vazio e o push\n'
  printf -- '  direto do ADMIN foi recusado (GH013). Ver `evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`\n'
  printf -- '- `precedencia de hooks nao confirmada`: medida - hooks de plugin SOMAM aos de usuario,\n'
  printf -- '  nao os sobrepoem. Ver `evidence/observations/2026-08-04-precedencia-de-hooks.md`\n'
  printf -- '- `required check ambiguo`: havia DOIS check-runs homonimos `verify` por SHA (eventos\n'
  printf -- '  push e pull_request), medidos com `gh api .../check-runs` sobre o head do PR #4\n'
  printf -- '  (total_count=2, ids 92057531104 e 92057522494). Separados em `verify-pr` (exigido) e\n'
  printf -- '  `verify-push` (nao exigido); travado por `tests/unit/fronteira-externa.sh` e morto por\n'
  printf -- '  `tests/mutation/fronteira.sh`\n'
  printf -- '- `claim ledger ancorava o NOME do arquivo`: o validador conferia que o arquivo existia\n'
  printf -- '  no snapshot; o conteudo citado podia ter mudado depois, e mudou (C-016). A ancora\n'
  printf -- '  passou a ser `blob_sha`, o conteudo. Caso L13 em `tests/unit/claims.sh`\n'
  printf -- '- `deploy managed podia deixar a arvore ativa parcial`: a copia ia direto no destino e\n'
  printf -- '  os portoes rodavam depois. Agora e staging com publicacao APOS os portoes; MG15\n'
  printf -- '  compara o digest da arvore inteira antes e depois de um deploy reprovado\n'
} > "$TMP"

if [ "$CHECK" -eq 1 ]; then
  if cmp -s "$TMP" "docs/status.generated.md"; then echo "status atualizado"; rm -f "$TMP"; exit 0
  else echo "docs/status.generated.md DESATUALIZADO - rode scripts/status.sh e commite"
       diff -u docs/status.generated.md "$TMP" | head -20; rm -f "$TMP"; exit 1; fi
fi
mv "$TMP" "$OUT"; echo "gerado: $OUT"
