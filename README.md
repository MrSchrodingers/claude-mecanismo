# evidence-gate

> **Harness experimental multirruntime para Claude Code Desktop, Claude Code CLI e Codex, orientado por evidência, falsificabilidade e fronteiras explícitas de autoridade.**

[![verify-pr](https://github.com/MrSchrodingers/evidence-gate/actions/workflows/verify-pr.yml/badge.svg)](https://github.com/MrSchrodingers/evidence-gate/actions/workflows/verify-pr.yml)

## Resumo

O `evidence-gate` parte de uma tese operacional simples:

> Um artefato só atravessa uma fronteira externa de integração quando uma política fora da autoridade do ator governado confirma evidência válida, não obsoleta e vinculada ao mesmo snapshot.

O projeto não tenta provar que um modelo de linguagem “está certo”. Ele constrói um sistema no qual alegações de conclusão precisam ser convertidas em observações executáveis, rastreáveis e refutáveis. Claude Code Desktop, Claude Code CLI e Codex podem explorar, planejar, implementar e reparar; qualquer sessão produz, no máximo, um **candidato**. A certificação pertence a uma verificação externa aplicada ao SHA exato e protegida por política de repositório.

O estado operacional corrente, incluindo contagens, componentes e limitações, é gerado por execução real em [`docs/status.generated.md`](docs/status.generated.md). Este README evita duplicar números mutáveis: a documentação já divergiu do mecanismo uma vez, e narrativa em cópia separada reproduz a classe de defeito que originou o projeto.

---

## 1. Escopo das afirmações

Este README distingue cinco classes de sustentação:

1. **Decisão arquitetural** — escolha de projeto, sujeita a revisão.
2. **Contrato oficial** — comportamento documentado por Claude Code, GitHub ou ferramenta primária.
3. **Evidência empírica local** — comportamento observado na máquina de desenvolvimento.
4. **Reprodução ambiental independente** — comportamento reproduzido em GitHub Actions.
5. **Hipótese ainda não testada** — afirmação que exige corpus, auditoria ou experimento posterior.

Os testes atuais sustentam a seguinte tese limitada:

> Certas garantias mecânicas do harness são falsificáveis, reproduzíveis no domínio exercitado e sensíveis à remoção deliberada de suas implementações.

Eles **não** sustentam a tese mais ampla:

> O harness melhora, de forma estatisticamente robusta e generalizável, a qualidade da engenharia produzida por agentes de código.

Em notação lógica, observar

\[
P(x_1),P(x_2),\ldots,P(x_n)
\]

não autoriza concluir

\[
\forall x\;P(x).
\]

A conclusão permitida é: `P` foi sustentada no domínio e nas condições testadas.

---

## 2. Modelo do sistema

### 2.1 Agente e harness

Adotamos o modelo operacional:

\[
Agent = Model + Harness
\]

com

\[
Harness = Context + Tools + Constraints + Verification + Correction.
\]

O modelo produz ações probabilísticas; o harness delimita contexto, ferramentas, autoridade, custo e critérios de aceitação. Essa separação segue a literatura contemporânea de engenharia de agentes e evita atribuir ao modelo capacidades que pertencem ao runtime ou aos verificadores [R1].

### 2.2 Três planos

```text
control/
    política, autoridade, integridade de configuração

execution/
    hooks, adaptadores, agentes, skills e ferramentas

evidence/
    verificadores, ledger, telemetria e CI
```

| Plano | Pergunta | Autoridade |
|---|---|---|
| `control/` | O que pode executar e sob qual política? | define capacidade e limites |
| `execution/` | Como o trabalho é realizado? | executa operações permitidas |
| `evidence/` | O que foi observado e sobre qual snapshot? | registra, verifica e certifica |

A separação reduz um erro recorrente: confundir o mecanismo que produz uma alteração com o mecanismo que autoriza sua integração.

### 2.3 Máquina de estados

```text
DRAFT
  -> LOCALLY_CHECKED
  -> CANDIDATE
  -> CI_VERIFIED
  -> MERGEABLE
```

Estados de falha:

```text
LOCAL_CHECK_FAILED
NOT_VERIFIED
CI_FAILED
STALE_EVIDENCE
```

`READY` não faz parte do vocabulário interno da sessão. O estado final da sessão é, no máximo, `CANDIDATE`.

Formalmente, para um artefato `x`, uma evidência `e` e uma política externa `P`:

\[
Mergeable(x) \iff Candidate(x) \land Valid(e,x) \land Fresh(e,x) \land Authorized(P,e).
\]

A validade exige vínculo ao snapshot:

\[
Valid(e,x) \Rightarrow e.snapshot = digest(x).
\]

A frescura exige que código, verificadores e ambiente relevantes não tenham mudado:

\[
Fresh(e,x) \iff H(x,v,env,policy)=e.evidence\_key.
\]

### 2.4 Núcleo canônico e projeções por runtime

A configuração multirruntime segue:

\[
Runtime_r = Core + Projection(Core,r).
\]

O núcleo normativo vive em `execution/` e `orchestration/`. As árvores `.claude/`, `.codex/`,
`.agents/skills/`, `CLAUDE.md` e `AGENTS.md` são projeções determinísticas produzidas por
`orchestration/render.py`. O teste `tests/unit/runtime-ports.sh` reprova inventário, conteúdo,
modo de arquivo, grafo ou referência divergente.

Essa construção evita três configurações manuais com autoridade concorrente. Ela prova
**convergência estrutural com a tradução declarada**, não equivalência semântica entre runtimes:
hooks, permissões, sandbox e modelos de confiança continuam sendo propriedades de cada
plataforma.

---

## 3. Fronteira e autoridade

Hooks locais, `Stop`, `TaskCompleted` e pre-commit produzem feedback; não certificam artefatos. A fronteira depende de status remoto obrigatório, vinculado ao SHA e sem bypass do ator governado.

## 4. Threat model e raiz de confiança

A política ativa ainda é `governed=user`. O instalador managed constrói staging, valida conteúdo e inodes e publica por renames verificados. Para falha observada com rollback bem-sucedido:

\[
CommitFailure \land RollbackSuccess \Rightarrow ActiveState_{after}=ActiveState_{before}.
\]

Se o próprio rollback falhar, retorna exit `70`, declara `ROLLBACK_FAILED` e preserva material de recuperação. Não cobre terminação que o shell não observa, sandbox de SO ou ativação administrativa ainda não realizada.

## 5. Evidência, cache e testes

O registro de evidência vincula snapshot, verificador, ambiente e política. Regressão, mutation testing, testes metamórficos e propriedades exigem pré-condições, tratamento aplicado e oráculo discriminante. Dependência ausente do oráculo é `NOT_VERIFIED`, nunca PASS.

## 6. Grafos de workflow e dependência

Os workflows canônicos estão em `orchestration/workflows/`. O renderizador publica uma visão humana e uma visão de máquina. Para qualquer grupo paralelo `G`:

\[
\sum_{n\in G} writes(n)=0.
\]

A cadeia padrão é `classify -> investigate/map -> plan -> RED -> implement -> tests -> review/refutation -> evidence -> CANDIDATE`. Mudanças de alto risco acrescentam threat model, auditoria e mutação.

## 7. Skills, agentes e subagentes

A topologia é selecionada por risco. Leitura e avaliação podem ocorrer em paralelo; escrita é serializada. Escritores usam worktree em Claude Code. Agentes Codex recebem sandbox declarado, sem que isso seja tratado como prova de isolamento de sistema operacional. A separação autor–avaliador reduz correlação de contexto, mas não cria independência estatística.

## 8. CI e enforcement

O contexto exigido é `verify-pr`; `verify-push` fornece feedback em push e não deve ser required. O workflow executa sintaxe, adaptadores, manifesto, projeções multirruntime, supply chain, document tools, reprodutibilidade, managed installer, propriedades, claim ledger, concorrência, status, regressões, quatro famílias de mutação e suíte legada.

## 9. Instalação

### Projeto — recomendado

```bash
python3 orchestration/render.py --check
bash tests/unit/runtime-ports.sh
```

### Claude global

```bash
bash install/apply.sh --dry-run
bash install/apply.sh
bash install/verify.sh
```

Windows:

```powershell
.\install\apply-claude-global.ps1 -DryRun
.\install\apply-claude-global.ps1
.\install\apply-claude-global.ps1 -Verify
```

Tutorial: [`docs/guides/windows-claude-code-desktop.md`](docs/guides/windows-claude-code-desktop.md).

## 10. Estrutura

```text
control/        política e integridade
execution/      fontes canônicas
orchestration/  registry, workflows e renderizador
.claude/        projeção Claude Code Desktop/CLI
.codex/         projeção Codex
.agents/skills/ projeção de Skills Codex
evidence/       gate, ledger, grafos e telemetria
install/        instalação e manifesto
tests/          regressão, propriedades, mutação e portabilidade
docs/           arquitetura, método, guias, ADRs e estado
```

## 11. Referências

- Anthropic, Claude Code documentation: https://code.claude.com/docs/
- OpenAI, Codex documentation: https://developers.openai.com/codex/
- GitHub, required status checks and rulesets: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets
- Jia; Harman, Mutation Testing, IEEE TSE 2011: https://doi.org/10.1109/TSE.2010.62
- Kambhampati et al., LLM-Modulo, ICML 2024: https://proceedings.mlr.press/v235/kambhampati24a.html
- Havrilla et al., GLoRe, ICML 2024: https://proceedings.mlr.press/v235/havrilla24a.html
- Zheng et al., personas in system prompts: https://arxiv.org/abs/2311.10054
- Han et al., SWE-Skills-Bench: https://arxiv.org/abs/2603.15401
- Zhong et al., SkillLearnBench: https://arxiv.org/abs/2604.20087

## 12. Limites declarados

- política ativa ainda gravável pelo ator;
- managed policy não ativada e cadeia ainda retorna ao checkout do ator;
- ambiente auditável, não hermético;
- sem sandbox real para parsers e comandos;
- equivalência multirruntime estrutural, não comportamental demonstrada em corpus;
- grafos de dependência ainda não avaliados contra `rg` e LSP;
- eficácia externa, custo-benefício e robustez comparativa não medidos;
- telemetria longitudinal e auditoria autoralmente independente ausentes.

Toda nova garantia deve incluir claim, rationale, contraexemplo, regressão, negativo ou mutante, precondições do oráculo, limites e execução em CI.
