# evidence-gate

Configuracao para Claude Code construida sobre uma regra:

> Um artefato so atravessa a fronteira externa quando uma politica **fora da autoridade do ator**
> confirma evidencia valida, nao obsoleta e vinculada ao mesmo snapshot.

O harness interno nao certifica nada. Ele eleva a probabilidade de chegar a esse estado com
baixo custo e baixo falso-bloqueio.

## Tres planos

| Plano | Conteudo | Autoridade |
|---|---|---|
| `control/` | politica, integridade de configuracao, disciplina de artefato | decide o que pode |
| `execution/` | hooks de execucao, adaptadores, agentes, skills | faz o trabalho |
| `evidence/` | verificador, ledger de vereditos, telemetria, CI | registra o que foi observado |

## O que este projeto aprendeu do jeito caro

**O repositorio nao era o sistema.** 32 componentes ativos, 12 versionados (37,5%). Quatro hooks
rodavam sem versionamento. O `verify-gate` instalado era uma versao anterior a do repositorio,
sem a camada que o manifesto declarava implementada. Por meses, sem sinal - porque nao existia
operacao de conferir. Ver `docs/adr/0022`.

**`Stop` nao e portao.** O runtime o sobrepoe apos N bloqueios consecutivos; `stop_hook_active`
libera a parada seguinte; `Stop` nao dispara em interrupcao nem em erro de API; e o proprio N
vive em `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, dentro do `settings.json` que o ator escreve.
Parametro de politica no espaco de escrita do governado nao e politica.

**`pre-commit` nao e fronteira.** Medido: `git commit --no-verify` cria o commit com o hook
reprovando. Feedback local, nao trust boundary.

## Verificacao

```
bash tests/unit/regressao-gate.sh   # cada caso reproduz um defeito medido
bash tests/unit/document-tools.sh   # executor documental, ponta a ponta
bash tests/unit/supply-chain.sh     # pinagem do gate externo
bash tests/unit/reprodutibilidade.sh# metamorfico: identidade invariante ao ambiente
bash tests/mutation/run.sh          # kill precisa ser atribuivel ao caso-alvo
bash tests/mutation/install.sh      # mutante do instalador
bash scripts/status.sh              # regenera docs/status.generated.md
bash install/verify.sh              # instalado == manifesto?
```

A validacao por mutacao nao e opcional: a suite anterior deste repositorio tinha 40 casos verdes
e sobreviveu ao false-green do verificador, porque contornava o mecanismo em vez de testa-lo.

## Instalacao

```
bash install/manifest.sh    # declara o estado desejado, com digest
bash install/apply.sh       # aplica em ~/.claude, com backup
bash install/verify.sh      # confere
```

`install/apply.sh --dry-run` mostra o plano sem escrever, remover ou criar backup - garantia
coberta pelo caso G10, que compara o digest do diretorio antes e depois byte a byte. Ela foi
quebrada uma vez: a convergencia por `--prune` rodava `rm -rf` antes de checar o modo.

Contagens, componentes e limites vivem em [`docs/status.generated.md`](docs/status.generated.md),
gerado por `scripts/status.sh` a partir de execucao real. Este README nao duplica numeros: ele
ja divergiu do mecanismo uma vez (afirmava 28 assercoes com a suite em 29), e narrativa em copia
separada se afasta sem sinal - a classe de defeito que originou este projeto.

## Limites declarados

- **A politica e gravavel pelo ator.** Esta fase e escopo de usuario. A raiz de confianca real
  exige managed settings, `allowManagedHooksOnly` e launcher nao gravavel - fase 2, com sudo,
  e so depois que todo hook estiver versionado, porque `allowManagedHooksOnly` desliga de uma
  vez todo hook de escopo de usuario.
- **Nao ha medicao de que isto melhora resultado de engenharia.** As suites verificam mecanismo
  sob fixture. Desfecho exigiria corpus dimensionado por poder estatistico, com repeticoes e
  analise hierarquica. Nao existe.
- **A CI so e enforcement se configurada como required status check** sem bypass para o ator.
  O workflow em `.github/workflows/verify.yml` e feedback ate que isso seja feito.
