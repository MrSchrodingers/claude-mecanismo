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
| `tests/unit/managed.sh` | 65 | 0 |
| `tests/unit/run.sh` | 53 | 0 |

## Mutacao

| Alvo | Mutantes | Exit |
|---|---:|---:|
| gate | 13 | 0 |
| contrato de subagente | 9 | 0 |
| instalador | 3 | 0 |
| fronteira externa | 7 | 0 |

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

- politica `governed=user`: os hooks ativos vivem em ~/.claude, gravavel pelo ator.
  O instalador managed (`install/apply-managed.sh`) esta CONSTRUIDO e exercitado contra
  prefixo de ensaio, mas `allowManagedHooksOnly` NAO foi ativado. Duas dependencias da
  cadeia seguem no espaco do ator: o proprio checkout de onde o instalador roda, e
  `EVIDENCE_GATE_REPO`, que o hook managed de SessionStart usa para achar o verificador.
- ambiente auditavel, nao hermetico: `ubuntu-24.04` fixa familia, nao digest
- sem corpus de desfecho: nenhuma afirmacao sobre eficacia de engenharia
- sem auditoria autoralmente independente: a CI e observador ambiental
- sem sandbox: parsers de documento rodam com a autoridade do usuario
- deploy managed: `DeployFail => ActiveState inalterado` vale para falha OBSERVADA
  (portao, jq, cp, chmod, chown, mv). NAO cobre terminacao que o shell nao observa -
  SIGKILL ou queda entre os dois renames da arvore deixa $OPT ausente. Fechar exigiria
  $OPT como symlink trocado por um unico rename, mudando layout, --verify e --revert
- o ruleset IMPOE, mas quem tem admin pode DESATIVA-LO: nao ha bypass dentro da
  regra (medido), e nao que a regra seja irremovivel

## Deixaram de ser limites (medidos em 2026-08-04)

- `CI executa mas NAO impoe`: o ruleset esta ativo com `bypass_actors` vazio e o push
  direto do ADMIN foi recusado (GH013). Ver `evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`
- `precedencia de hooks nao confirmada`: medida - hooks de plugin SOMAM aos de usuario,
  nao os sobrepoem. Ver `evidence/observations/2026-08-04-precedencia-de-hooks.md`
- `required check ambiguo`: havia DOIS check-runs homonimos `verify` por SHA (eventos
  push e pull_request), medidos com `gh api .../check-runs` sobre o head do PR #4
  (total_count=2, ids 92057531104 e 92057522494). Separados em `verify-pr` (exigido) e
  `verify-push` (nao exigido); travado por `tests/unit/fronteira-externa.sh` e morto por
  `tests/mutation/fronteira.sh`
- `claim ledger ancorava o NOME do arquivo`: o validador conferia que o arquivo existia
  no snapshot; o conteudo citado podia ter mudado depois, e mudou (C-016). A ancora
  passou a ser `blob_sha`, o conteudo. Caso L13 em `tests/unit/claims.sh`
- `deploy managed podia deixar a arvore ativa parcial`: a copia ia direto no destino e
  os portoes rodavam depois. Agora e staging com publicacao APOS os portoes; MG15
  compara o digest da arvore inteira antes e depois de um deploy reprovado
- `falha POS-publicacao alterava o estado ativo`: achado por revisao independente do
  PR #5. A arvore era publicada e a anterior APAGADA antes de `managed-settings.json`
  ser gerado e instalado, com `jq`/`cp`/`chmod`/`chown` sem retorno verificado. Agora
  a politica e gerada e validada ANTES de tocar o estado ativo, a fase de commit so
  contem renames verificados, e o material de rollback so e descartado quando arvore e
  politica ja estao no lugar. MG17 usa `MANAGED_FAILPOINT` para provocar a falha
  pos-publicacao; MI3 e o mutante atribuivel
