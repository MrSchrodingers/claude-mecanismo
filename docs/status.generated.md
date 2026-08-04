# Estado gerado

NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.
O README referencia este arquivo em vez de duplicar numeros.

## Suites

| Suite | Assercoes | Exit |
|---|---:|---:|
| `tests/unit/regressao-gate.sh` | 34 | 0 |
| `tests/unit/document-tools.sh` | 21 | 0 |
| `tests/unit/supply-chain.sh` | 6 | 0 |
| `tests/unit/reprodutibilidade.sh` | variavel (ambiente) | 0 |
| `tests/unit/concorrencia.sh` | 8 | 0 |
| `tests/unit/claims.sh` | 18 | 0 |
| `tests/unit/propriedades.sh` | 22 | 0 |
| `tests/unit/managed.sh` | 42 | 0 |
| `tests/unit/run.sh` | 52 | 0 |

## Mutacao

| Alvo | Mutantes | Exit |
|---|---:|---:|
| gate | 10 | 0 |
| contrato de subagente | 9 | 0 |
| instalador | 1 | 0 |

## Componentes

| Tipo | Qtd |
|---|---:|
| adapter | 11 |
| agent | 10 |
| doctool | 5 |
| hook | 14 |
| skill | 9 |
| **total** | **49** |

## Limites declarados

- politica `governed=user`: alteravel pelo ator governado; raiz de confianca nao implementada
- ambiente auditavel, nao hermetico: `ubuntu-24.04` fixa familia, nao digest
- sem corpus de desfecho: nenhuma afirmacao sobre eficacia de engenharia
- sem auditoria autoralmente independente: a CI e observador ambiental
- sem sandbox: parsers de documento rodam com a autoridade do usuario
- o ruleset IMPOE, mas quem tem admin pode DESATIVA-LO: nao ha bypass dentro da
  regra (medido), e nao que a regra seja irremovivel

## Deixaram de ser limites (medidos em 2026-08-04)

- `CI executa mas NAO impoe`: o ruleset esta ativo com `bypass_actors` vazio e o push
  direto do ADMIN foi recusado (GH013). Ver `evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`
- `precedencia de hooks nao confirmada`: medida - hooks de plugin SOMAM aos de usuario,
  nao os sobrepoem. Ver `evidence/observations/2026-08-04-precedencia-de-hooks.md`
