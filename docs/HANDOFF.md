# Handoff - fechamento da Fase 1 (M2 -> M3)

- Origem: sessao de 2026-08-03, `claude-mecanismo` -> `evidence-gate`
- Ultimo commit desta sessao: `819b952`
- Estado: **M2 - mecanismo experimental verificado, reproduzido em ambiente independente**
- Alvo da proxima sessao: **M3 - enforcement operacional e raiz de confianca**

---

## 1. Leia isto antes de qualquer coisa

**O que este projeto e:** uma configuracao de Claude Code cuja regra unica e

> Um artefato so atravessa a fronteira externa quando uma politica **fora da autoridade do ator**
> confirma evidencia valida, nao obsoleta e vinculada ao mesmo snapshot.

**O que ele NAO e, hoje:** uma fronteira de confianca. A politica ainda e gravavel pelo ator
governado; a CI executa mas nao impede merge. Isso esta declarado em `README.md`, no ADR 0022 e
em `docs/status.generated.md`. Nao o descreva como garantia.

**Onde esta a verdade:** `docs/status.generated.md`, gerado por `scripts/status.sh` a partir de
execucao real. Nunca digite contagens a mao em lugar nenhum - o README ja divergiu uma vez, e a
correcao foi parar de duplicar, nao corrigir o numero.

---

## 2. O contrato de teste deste repositorio

Cinco defeitos desta sessao tiveram a mesma forma, e a defesa contra ela e a regra mais
importante do projeto:

```
precondicao falha -> operacao nao executa -> pos-condicao vacuamente verdadeira -> VERDE
```

| Onde ocorreu | O que nao executou | Defesa construida |
|---|---|---|
| `--dry-run` | o `cd` falhou; nada rodou | exit code da operacao vira assercao |
| locale | `LC_ALL=pt_BR` sem o locale instalado | discriminador comportamental |
| locale, 2a tentativa | `locale` ecoa nome de locale inexistente | idem |
| matcher do `apt` | `apt-get -o ... install` nao casava | contagem invariante (`EXPECTED`) |
| `packaging` em S5 | SKIP reduzia o esperado junto | pre-requisito de oraculo obrigatorio |

Logo, **um teste novo neste repositorio nao vale sem**:

```
precondicoes satisfeitas
  E tratamento efetivamente aplicado
  E oraculo capaz de discriminar
  E operacao comprovadamente executada
  E Q(estado_final)
```

E a distincao que decide como tratar um pre-requisito ausente:

| Tipo | Ausente significa | Tratamento |
|---|---|---|
| **dependencia do ORACULO** (ex.: `packaging`) | o teste **nao foi realizado** | `exit 2`, NOT_VERIFIED |
| **variacao de AMBIENTE** (ex.: locales instalados) | uma variante nao pode ser exercitada | `SKIP` + assercao-guarda exigindo ao menos uma |

---

## 3. Rigor exigido - nao negociavel

1. **Reproduza antes de corrigir.** Todo defeito comeca por um comando que o exibe, com saida
   colada. Sem repro, nao ha o que corrigir - ha o que supor.
2. **Corrija a CLASSE, nao a instancia.** `pymupdf` sem versao virou `tests/unit/supply-chain.sh`,
   nao um pin. Drift de README virou `scripts/status.sh`, nao um numero editado.
3. **Todo teste novo passa por mutacao.** Remova a garantia, exija que a suite reprove, e que
   reprove **no caso-alvo correspondente**. Mutante nao aplicado e FALHA, nao sobrevivencia.
4. **Contagem e invariante.** `EXPECTED` fixo; caso que some reprova. Nunca reduza o esperado
   para acomodar um SKIP.
5. **Fonte primaria para todo fato externo.** Quatro erros desta sessao foram afirmacoes sem
   conferir a fonte (LSP, SkillLearnBench, `dotnet format`, pinagem). O adaptador .NET declarava
   `executes_repository_code: false` contra a advertencia explicita da Microsoft.
6. **Estado sem execucao colada e NAO VERIFICADO.** Nao existe "deve funcionar".
7. **Sem emoji, sem hype, em qualquer artefato.** `control/hooks/artifact-discipline.sh` barra.

---

## 4. Como rodar (comece por aqui)

```bash
cd ~/evidence-gate

# 1. estado atual, por execucao real
bash scripts/status.sh && cat docs/status.generated.md

# 2. conformidade repo <-> ~/.claude
bash install/verify.sh

# 3. suites (todas devem sair 0)
bash tests/unit/supply-chain.sh
bash tests/unit/reprodutibilidade.sh
bash tests/unit/document-tools.sh
bash tests/unit/regressao-gate.sh
bash tests/unit/run.sh
bash tests/mutation/run.sh
bash tests/mutation/install.sh

# 4. aplicar mudancas em ~/.claude (sempre com backup automatico)
bash install/apply.sh --dry-run    # plano, sem escrever
bash install/apply.sh              # aplica e roda verify

# 5. gate externo
gh run list --limit 3
```

Backup desta sessao, se precisar reverter:
`~/.claude/backups/pre-evidence-gate-20260803-164632`

---

## 5. O que falta, em ordem de execucao

### P0 - fechavel na proxima sessao

**P0.1 Confirmar o runtime efetivo.** ESTE ITEM EXIGE O USUARIO: `/hooks`, `/status` e
`--debug` sao comandos do CLI, nao executaveis por Bash. Peca a saida e registre.
Objetivo: preencher `desired / installed / loaded / executed / governed_by`.
**Por que importa:** o ADR 0022 declara que uma precedencia diferente entre hooks de usuario e
plugins **refutaria parte do diagnostico**. Enquanto nao for observado, o diagnostico central
tem uma premissa aberta.

**P0.2 Claim ledger.** `evidence/claims/*.yaml` + validador de schema + caso na CI.
Schema minimo (o `counterexamples` e a parte mais valiosa - registro de refutacao):

```yaml
claim_id: C-001
claim: "Falha em cache nunca e reutilizada como sucesso."
type: empirical-invariant
scope:
  commit: 819b952
  platforms: [local-linux, github-ubuntu-24.04]
evidence:
  regression: [G1]
  mutants: [M1]
  ci_run: "<url>"
warrant: "o mutante que remove a distincao fail/pass e morto por G1"
counterexamples:
  - commit: <o commit onde falhava>
    result: refuted
limitations: ["nao testado em macOS", "nao e prova universal"]
status: supported-in-tested-domain
```

Regra: o ledger **referencia** evidencia existente, nao a duplica. E precisa de um teste que
reprove se uma claim citar um `regression:` ou `mutant:` que nao existe.

**P0.3 Base de comparacao sem upstream.** Hoje, commit local sem `@{u}` some do conjunto de
mudancas: `git diff HEAD` vazio + untracked vazio + sem upstream = gate inerte. Definir a base
(merge-base com a branch default, commit inicial da sessao, ou ultimo ledger) e adicionar caso
de regressao.

**P0.4 Property-based testing.** Alvos: substituicao de placeholders no `doctool.sh`, filenames
hostis, normalizacao de paths, parser do workflow, identidade do manifesto. Mesma familia
epistemica dos metamorficos que ja pagaram, sem artefato paralelo para manter.

### P1 - exige acao do usuario no GitHub

**Required status check + ruleset sem bypass para o ator.** Sem isso `CI = feedback`; com isso
`CI + ruleset = external gate`. Confirmar que o check e exigido sobre o **SHA exato** e que o
ator governado nao pode contornar. Depois disso, e so depois, o README pode dizer "enforcement".

### P2 - raiz de confianca (exige sudo)

`managed settings` root-owned + `allowManagedHooksOnly` + launcher nao gravavel.
**ARMADILHA:** `allowManagedHooksOnly` desliga de uma vez TODO hook de escopo de usuario. Os 14
hooks precisam estar em plugin force-enabled ou managed ANTES de ativar, senao o mecanismo
inteiro cai. Migrar, verificar, so entao ativar.

### P3 - hardening

- **Sandbox**: parsers de documento (`pandoc`, `libreoffice`, `pdftotext`) rodam hoje com a
  autoridade do usuario sobre entrada nao-confiavel. D5 impoe timeout, teto de bytes e tmpdir -
  isso e contencao de recurso, **nao isolamento**.
- **Hermeticidade**: `ubuntu-24.04` fixa familia, nao digest. Container por digest + SBOM.
- **Cache de extracoes** no `doctool.sh` (o digest ja esta no pack; falta a camada e a invalidacao).

### P4 - eficacia (NAO cabe numa sessao)

Corpus congelado, primeiro contraste `baseline vs harness minimo`, metricas `UAR/URR/AR/VY`,
piloto para estimar `p01`/`p10`, power analysis, contraste pre-registrado, modelo logistico
hierarquico. **Sem isso nenhuma afirmacao sobre melhoria de engenharia e dizivel.**

### P5 - auditoria autoralmente independente

A CI e observador **ambiental**, nao autoral: executa os testes escritos pelo mesmo processo,
contra os mesmos oraculos. Auditoria real precisa de mutantes nao revelados e fixtures hostis
de terceiro. Este e o gargalo que nenhuma sessao minha resolve.

### Nao priorizar agora

**Metodos formais (TLA+/Alloy).** Dos ~11 defeitos desta sessao, zero eram violacao de
invariante da maquina de estados; todos eram precondicao nao satisfeita, dependencia nao
declarada, matcher cego ou classificacao errada. Especificacao formal cria um segundo artefato
que pode divergir do primeiro - o defeito `repo != runtime` transposto. Gatilho legitimo para
reavaliar: concorrencia no ledger, corrida entre snapshot e verificacao, composicao de
autoridades, ou estado inalcancavel aparecendo em producao.

**Grafos.** Estagio exploratorio (skill + hook + agente, sem schema, digest, freshness ou
benchmark). Nao priorizar sobre claim ledger, corpus ou auditoria. Quando for a hora: LSP antes
de indice proprio - o Claude Code tem caminho oficial via `.lsp.json` em plugin, o que e
configurar e nao construir.

---

## 6. Armadilhas que ja custaram tempo

1. **`$(...)` em substituicao de comando cria subshell** - `R=$(funcao)` perde o `cd`. Os casos
   rodavam no diretorio do caso anterior e davam PASS/FAIL por motivo errado.
2. **`head`/`tail` num pipe destroem o exit code.** `cmd | head` devolve o status do `head`.
   Aconteceu tres vezes; duas quase produziram conclusao errada.
3. **`CLAUDE_ADAPTERS_DIR` vive no `settings.json`** e entra no ambiente das ferramentas: a
   suite chegou a exercitar a copia instalada em `~/.claude` em vez do repositorio.
4. **`pandoc -o x.pdf` exige engine LaTeX** - ausente na CI. Fixtures de PDF por PyMuPDF.
5. **`locale` ecoa o nome pedido mesmo para locale inexistente.** Verificar nome nao verifica
   efeito; use discriminador comportamental.
6. **`sed 'y/.../.../'` quebra sob `LC_ALL=C`** com multi-byte. Substituicao literal por byte.
7. **As suites NAO sao reentrantes.** `G10` executa `install/apply.sh`, que escreve
   `install/manifest.lock` e `~/.claude`. Duas execucoes concorrentes se corrompem: medido, uma
   deu `29/exit 0` e a simultanea `27/exit 1`. Isoladas, tres execucoes seguidas dao 29/29.
   Na CI e sequencial, entao nao aparece la. **Rode uma suite por vez**; se um comando ficou em
   background, espere. Corrigir de verdade exigiria lock no diretorio de trabalho - escopo aberto.
8. **`$TMPDIR` pode estar vazio no zsh** - `"$TMPDIR/x"` vira `/x` e falha com permission denied.

---

## 7. Criterio de pronto desta proxima sessao

Nao declare a sessao concluida sem, colado na resposta:

- [ ] `bash scripts/status.sh --check` -> exit 0
- [ ] `bash install/verify.sh` -> exit 0, sem orfaos
- [ ] as 5 suites unitarias e os 2 runners de mutacao -> exit 0
- [ ] CI verde no commit final, com o SHA e a URL do run
- [ ] `docs/status.generated.md` regenerado e committado
- [ ] ADR atualizado com o que foi feito **e com o que nao foi**
- [ ] cada item de P0 marcado: fechado / nao fechado / bloqueado por acao do usuario

E o portao final: **delegue ao agente `refutador`** com o `git diff` cru da sessao. Contexto
separado, instrucao para tentar refutar. Esta sessao nao o acionou por restricao do ambiente, e
essa lacuna esta declarada - se a proxima puder, deve.

## 8. Como NAO fechar

"Fechar TUDO" nao e alcancavel numa sessao. P4 (corpus, inferencia) leva semanas; P5 exige um
terceiro. Prometer o fechamento total repetiria exatamente a classe de defeito que este projeto
existe para impedir: **declarar pronto o que nao foi executado**.

O fechavel numa sessao limpa e: **P0 inteiro, P1 e P2 na parte que o usuario autorizar e
executar, P3 parcial.** O resto deve sair da sessao com escopo escrito e limites declarados.
