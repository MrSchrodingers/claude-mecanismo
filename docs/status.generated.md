# Estado gerado

NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.
O README referencia este arquivo em vez de duplicar numeros.

## Suites

| Suite | Assercoes | Exit |
|---|---:|---:|
| `tests/unit/regressao-gate.sh` | 29 | 0 |
| `tests/unit/document-tools.sh` | 21 | 0 |
| `tests/unit/supply-chain.sh` | 6 | 0 |
| `tests/unit/reprodutibilidade.sh` | variavel (ambiente) | 0 |
| `tests/unit/run.sh` | 45 | 0 |

## Mutacao

| Alvo | Mutantes | Exit |
|---|---:|---:|
| gate | 9 | 0 |
| contrato de subagente | 5 | 0 |
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
- CI executa mas NAO impoe: falta required status check e ruleset sem bypass
- ambiente auditavel, nao hermetico: `ubuntu-24.04` fixa familia, nao digest
- sem corpus de desfecho: nenhuma afirmacao sobre eficacia de engenharia
- sem auditoria autoralmente independente: a CI e observador ambiental
- sem sandbox: parsers de documento rodam com a autoridade do usuario
- precedencia de hooks no runtime nao confirmada (`/hooks`, `--debug`)
