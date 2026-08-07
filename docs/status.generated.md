# Estado gerado

NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.
O README referencia este arquivo em vez de duplicar numeros.

## Suites

| Suite | Assercoes | Exit |
|---|---:|---:|
| `tests/unit/regressao-gate.sh` | 41 | 0 |
| `tests/unit/document-tools.sh` | 21 | 0 |
| `tests/unit/supply-chain.sh` | 6 | 0 |
| `tests/unit/reprodutibilidade.sh` | variavel (ambiente) | 0 |
| `tests/unit/concorrencia.sh` | 8 | 0 |
| `tests/unit/claims.sh` | 37 | 0 |
| `tests/unit/propriedades.sh` | 22 | 0 |
| `tests/unit/fronteira-externa.sh` | 11 | 0 |
| `tests/unit/runtime-ports.sh` | 150 | 0 |
| `tests/unit/managed.sh` | 78 | 0 |
| `tests/unit/run.sh` | 53 | 0 |

## Mutacao

| Alvo | Mutantes | Exit |
|---|---:|---:|
| gate | 13 | 0 |
| contrato de subagente | 9 | 0 |
| instalador | 7 | 0 |
| fronteira externa | 7 | 0 |

## Componentes

49 componentes: 11 adaptadores, 10 agentes, 5 doctools, 14 hooks e 9 Skills.

## Limites

Política de usuário ainda gravável; managed policy não ativada; ambiente não hermético; sem sandbox; sem corpus de eficácia ou auditoria independente. Para falha observada com rollback bem-sucedido, o estado ativo retorna ao anterior. Falha do rollback retorna 70, declara `ROLLBACK_FAILED` e preserva recuperação. Equivalência multirruntime é estrutural, não semântica demonstrada.
