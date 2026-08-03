# ADR 0022 - Tres planos, e a fronteira que o ator nao controla

- Data: 2026-08-03
- Status: aceito
- Corrige: 0010, 0015, 0016, 0020 (todos tratavam `Stop` como portao de conclusao)
- Renomeia o projeto: `claude-mecanismo` -> `evidence-gate`

## O achado que subordinou todos os outros

O repositorio nao era o sistema. Medido em 2026-08-03, claude-code 2.1.220:

| Componente | Ativo | Versionado | Cobertura |
|---|---|---|---|
| Hooks | 13 | 9 (1 divergente) | 62% |
| Skills | 9 | 2 | 22% |
| Agentes | 10 | 1 | 10% |
| **Total** | **32** | **12** | **37,5%** |

Quatro hooks rodavam em toda sessao sem versionamento, teste ou ADR. E o `verify-gate.sh`
instalado era uma versao **anterior** a do repositorio - sem a camada de adaptadores que o
`plugin.json` declarava implementada e que o ADR 0011 registrava como corrigida:

```
grep -c "ADAPTERS" ~/.claude/hooks/verify-gate.sh  ->  0
```

Este projeto passou 21 ADRs combatendo prosa-como-garantia e produziu um repositorio que era,
ele mesmo, prosa sobre um sistema divergente. Nao era um bug: era um estado que nao deveria ser
alcancavel. Nao existia operacao de instalar nem de conferir, so `cp` - e copia diverge calada.

## O erro de categoria

`Stop` foi tratado como portao de conclusao desde o ADR 0010. Ele nao pode ser, por quatro
razoes independentes:

1. `stop_hook_active=true` na parada seguinte a um bloqueio - semantica anti-loop oficial;
2. o runtime **sobrepoe** o hook apos N bloqueios consecutivos (default 8);
3. esse N vive em `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, dentro do `settings.json` que o proprio
   ator governado escreve;
4. `Stop` nao dispara em interrupcao do usuario nem em falha de API.

A razao 3 e a estrutural e generaliza: **parametro de politica dentro do espaco de escrita do
ator governado nao e politica.** Vale igualmente para `disableAllHooks`, `enabledPlugins`,
`permissions`, `env` e `hooks`.

E `pre-commit` tambem nao e fronteira. Medido:

```
git commit             -> exit=1, 0 commits   (hook barrou)
git commit --no-verify -> exit=0, 1 commit    (codigo reprovado entrou na historia)
```

A propriedade correta nunca e absoluta. E sempre relativa: `¬bypass(ator, politica P)`.

## Decisao

### Tres planos, com autoridades distintas

```
control/    politica, autoridade, integridade de configuracao
execution/  hooks de execucao, adaptadores, agentes, skills
evidence/   verificador, ledger, telemetria, CI
```

### A cadeia de estados perde `READY`

```
DRAFT -> LOCALLY_CHECKED -> CANDIDATE -> CI_VERIFIED -> MERGEABLE
falhas: LOCAL_CHECK_FAILED | NOT_VERIFIED | CI_FAILED | STALE_EVIDENCE
```

A sessao produz no maximo `CANDIDATE`. Quem certifica e a CI sobre o SHA exato.

### Cinco garantias do verificador, cada uma com repro e mutante

| # | Garantia | Defeito que pagou |
|---|---|---|
| G1 | cache guarda VEREDITO; `fail` nunca vira verde | carimbo gravado antes de executar: 2a parada saia 0 com codigo quebrado |
| G2 | `stop_hook_active` avisa por `additionalContext` | stderr com exit 0 e canal inerte (ADR 0021) |
| G3 | identidade sobre BYTES | hash de nomes nao ve conteudo de untracked |
| G4 | conjuncao sobre TODOS os adaptadores | monorepo: JS valido mascarava Python quebrado |
| G5 | `command` + `args`, sem `sh -c` | string em shell permite composicao arbitraria |

### Manifesto, instalador, verificador

Nao existe instalar manualmente. `install/manifest.sh` declara o estado desejado com digest;
`install/apply.sh` aplica; `install/verify.sh` compara; `control/hooks/session-integrity.sh`
denuncia divergencia no primeiro turno da sessao.

## O que este ADR NAO resolve

**A politica continua gravavel pelo ator.** Esta fase e escopo de usuario. A raiz de confianca
real exige managed settings + `allowManagedHooksOnly` + launcher nao gravavel, e nao foi feita
porque `allowManagedHooksOnly` desliga de uma vez todo hook de escopo de usuario - ativa-lo
antes de migrar os 14 hooks derrubaria o mecanismo inteiro. Fase 2, com sudo, apos validacao.

**Nao ha medicao de desfecho.** As suites verificam mecanismo sob fixture. Que o harness
melhore resultado de engenharia continua nao demonstrado, agora com um agravante conhecido:
`SWE-Skills-Bench` (arXiv:2603.15401) tem ~11 tarefas por skill, e 24 das 49 skills saturaram
em 100% nas duas condicoes - o benchmark nao tinha margem para detectar ganho nessas. Alem
disso, `ΔP=0` significa `n01=n10`, nao `n01=n10=0`: os 39 deltas nulos nao demonstram que as
condicoes acertaram as mesmas tarefas. Dimensionar corpus exige `q=p01+p10` e `d=p01-p10`,
que o artigo nao publica.

**`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` nao foi verificado.** O default 8 esta documentado; a
semantica de zero veio de fonte secundaria. Plano de teste: cap=2, hook que sempre bloqueia,
contador persistente, timeout externo.

## O que refutaria este ADR

Se `~/.claude` nao fosse o escopo efetivo - por exemplo, se plugins instalados sobrescrevessem
os hooks em tempo de execucao. A precedencia entre `~/.claude/hooks` e `~/.claude/plugins/` nao
foi verificada com `/hooks` nem `--debug`.

## Adendo 2026-08-03 - achados de revisao independente

Revisao externa do estado publicado encontrou oito defeitos. Todos verificados; sete corrigidos.

### Regressao de seguranca minha, confirmada na fonte primaria

O adaptador .NET declarava `executes_repository_code: false` sobre `dotnet format
--verify-no-changes --no-restore`. A documentacao da Microsoft adverte o contrario:

> `dotnet format` **may restore, compile, and run analyzers** from the specified project or
> solution. **Only invoke the tool against trusted code.**

`--no-restore` suprime apenas o restore implicito - nao a compilacao nem os analisadores, que
sao codigo do repositorio. Escrevi a justificativa sem conferir a fonte: e o terceiro erro
desta classe no projeto, sob vigilancia nominal da regra que existe para impede-lo.

Corrigido como REGRA GERAL, nao caso especial (G10): adaptador que declara
`executes_repository_code: true` nunca roda em auto-deteccao - vira lacuna declarada.

### Demais correcoes

| # | Defeito | Correcao |
|---|---|---|
| G9 | `jq`/`git` ausentes saiam 0 em silencio - a mesma inercia que G7 combate, no caminho mais critico | dependencia estrutural ausente e NOT_VERIFIED; fora de repo git, inerte segue legitimo |
| G11 | `environment_digest` hasheava so o CAMINHO do binario; troca do executavel no mesmo path preservava o `pass` em cache | inclui realpath, sha256 do binario e string de versao |
| - | `apply.sh` nao removia componente que saiu do manifesto: `apply` nao convergia para `desired` | `managed-files.lock`; remove apenas o que ele mesmo gerenciou, nunca arquivo desconhecido |
| - | skills eram conferidas contra a working tree, deixando o manifesto fora do circuito | digest com caminho normalizado; `REPO-DRIFT` distinguido de `installation drift` |
| - | contagem de casos era descritiva: apagar cinco testes mantinha a suite verde | `EXPECTED` como invariante |
| - | mutante era considerado morto por qualquer reprovacao, e `sed` que nao casava virava "sobreviveu" | baseline obrigatorio; kill precisa ser atribuivel ao caso-alvo; mutante nao aplicado e FALHA |
| - | CI usava `actions/checkout@v4`, `ubuntu-latest` e ruff sem versao - tags mutaveis numa fronteira de evidencia | action pinada por SHA completo, `ubuntu-24.04`, `ruff==0.15.5` |

O mutante M7 sobreviveu a primeira tentativa e revelou que o caso G7 nao distinguia "lacuna por
ser executor" de "lacuna por binario ausente" - assercao especifica adicionada. Segunda vez
nesta sessao que a mutacao encontra teste fraco que a suite verde nao mostrava.

### Nao corrigido, e por que

- **`.claude/verify.json` aprovado ainda SUBSTITUI os analisadores genericos** em vez de somar.
  A formula real e `Pass(v_repo,x)` quando aprovado, nao a conjuncao. E override semantico
  deliberado (o projeto sabe o que verificar), mas estava descrito como conjuncao irrestrita.
- **A aprovacao cobre o digest de `verify.json`, nao o conteudo transitivo.** Aprovar
  `{"command":"bash","args":["scripts/verify.sh"]}` autoriza um script que pode mudar depois.
  A aprovacao significa "confio que este repositorio execute sua suite", nao "confirmei os
  bytes que rodarao". Solucao real e sandbox, nao aprovacao.
- **Commit local sem upstream nao e verificado**: `git diff HEAD` e untracked ficam vazios apos
  commit, e sem `@{u}` nao ha base. Exige definir a base (merge-base, commit inicial da sessao
  ou ledger anterior).
- **Adaptadores de documento sao especificacao versionada, nao mecanismo executado.** Nenhum
  executor os consome: `read-budget.sh` mantem logica propria por extensao.

## Adendo 2 - a garantia nova que quebrou o modo seguro

Segunda revisao independente, sobre o commit `9ddb1fa`. Cinco achados; todos procedentes.

### Critico: `--dry-run` passou a apagar arquivo

Ao adicionar a convergencia (`managed-files.lock`), o bloco de remocao ficou ANTES da checagem
`[ "$DRY" -eq 1 ] && exit 0`. O modo anunciado como inspecao segura executava `rm -rf`.

Medido antes da correcao, em HOME descartavel:

```
digest apos adicionar orfao ... a87423aa7c659c48
DEPOIS do --dry-run .......... a32a09c13da42d79   <- estado alterado
arquivo orfao FOI APAGADO pelo dry-run
```

Este defeito e a tese do projeto aplicada a si mesmo: **adicionar uma garantia de convergencia
nao prova que os demais modos da operacao, em especial o modo declaradamente nao destrutivo,
preservam a garantia.** Corrigido com portao antes de qualquer escrita, e coberto por G10, que
compara o digest do diretorio byte a byte, mais o mutante MI1 em `tests/mutation/install.sh`.

### Demais

| # | Defeito | Correcao |
|---|---|---|
| G9b | `command -v git \|\| exit 0` seguia fail-open; so `jq` fora corrigido | sobe a arvore atras de `.git` sem usar git; havendo `.git` e faltando git, NOT_VERIFIED |
| - | contagem publicava "9 mortos" para 8 mutantes: o baseline incrementava o mesmo contador | `BASELINE` separado; `EXPECTED_MUTANTS` como invariante |
| - | `environment_digest` truncava o sha256 do binario em 16 hex (64 bits), descrito como "sha256 do binario" | hash completo; numa identidade de evidencia nao ha ganho em truncar |
| - | "heartbeat em toda sessao" era mais forte que o codigo | limite escrito no hook: ha heartbeat em toda execucao que ultrapassa as precondicoes; ausencia nao implica drift |

### Limite que permanece em G10 (executor nao roda sozinho)

A regra confia no valor DECLARADO em `declared_effects.executes_repository_code`. O defeito
anterior foi exatamente uma declaracao falsa. Logo G10 impede execucao de adaptador
CORRETAMENTE classificado; nao detecta classificacao errada. Contra isso valem revisao de
fonte, mutacao e corpus hostil - nao a regra.
