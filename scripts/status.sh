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
           tests/unit/claims.sh tests/unit/propriedades.sh tests/unit/run.sh; do
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
  bash tests/mutation/install.sh >/dev/null 2>&1
  printf '| instalador | 1 | %s |\n' "$?"
  printf '\n## Componentes\n\n| Tipo | Qtd |\n|---|---:|\n'
  awk -F'\t' '!/^#/{c[$1]++} END{for(t in c) printf "| %s | %s |\n", t, c[t]}' install/manifest.lock | sort
  printf '| **total** | **%s** |\n' "$(grep -vc '^#' install/manifest.lock)"
  printf '\n## Limites declarados\n\n'
  printf -- '- politica `governed=user`: alteravel pelo ator governado; raiz de confianca nao implementada\n'
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
} > "$TMP"

if [ "$CHECK" -eq 1 ]; then
  if cmp -s "$TMP" "docs/status.generated.md"; then echo "status atualizado"; rm -f "$TMP"; exit 0
  else echo "docs/status.generated.md DESATUALIZADO - rode scripts/status.sh e commite"
       diff -u docs/status.generated.md "$TMP" | head -20; rm -f "$TMP"; exit 1; fi
fi
mv "$TMP" "$OUT"; echo "gerado: $OUT"
