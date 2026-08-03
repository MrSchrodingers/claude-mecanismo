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
