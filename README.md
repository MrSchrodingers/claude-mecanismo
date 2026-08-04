# evidence-gate

> **Harness experimental para Claude Code orientado por evidência, falsificabilidade e fronteiras explícitas de autoridade.**

[![verify-pr](https://github.com/MrSchrodingers/evidence-gate/actions/workflows/verify-pr.yml/badge.svg)](https://github.com/MrSchrodingers/evidence-gate/actions/workflows/verify-pr.yml)

## Resumo

O `evidence-gate` parte de uma tese operacional simples:

> Um artefato só atravessa uma fronteira externa de integração quando uma política fora da autoridade do ator governado confirma evidência válida, não obsoleta e vinculada ao mesmo snapshot.

O projeto não tenta provar que um modelo de linguagem “está certo”. Ele constrói um sistema no qual alegações de conclusão precisam ser convertidas em observações executáveis, rastreáveis e refutáveis. O Claude Code pode explorar, planejar, implementar e reparar; a sessão produz, no máximo, um **candidato**. A certificação pertence a uma verificação externa aplicada ao SHA exato e protegida por política de repositório.

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

---

## 3. Por que `Stop`, `TaskCompleted` e pre-commit não são a fronteira

### 3.1 `Stop`

A documentação oficial do Claude Code estabelece que:

- `Stop` executa quando o agente termina uma resposta;
- não executa em interrupção do usuário;
- falhas de API produzem `StopFailure`;
- `stop_hook_active=true` indica continuação causada por um Stop hook;
- `exit 2` pede que o agente continue, mas não certifica um artefato [R2].

Portanto:

\[
StopBlocked \not\Rightarrow ArtifactCertified.
\]

No `evidence-gate`, o Stop hook é um mecanismo de feedback e reparo. Ele pode bloquear uma tentativa de parada ou retornar `additionalContext`, mas não constitui trust boundary.

### 3.2 `TaskCompleted`

`TaskCompleted` impede que uma tarefa explícita seja marcada como concluída. Não governa toda sessão, todo commit ou todo merge [R2]. Logo:

\[
TaskCompletedPass \not\Rightarrow Mergeable.
\]

### 3.3 pre-commit

Hooks Git locais podem ser ignorados com `git commit --no-verify`. Assim:

\[
PreCommit = Feedback_{local}
\]

mas

\[
PreCommit \neq TrustBoundary.
\]

A fronteira só existe quando um status remoto é obrigatório e o ator governado não pode alterar ou contornar a política:

\[
ExternalGate(P,a) \iff RequiredCheck(P) \land \neg Bypass(a,P).
\]

A propriedade é sempre relativa ao ator e à política, nunca absoluta.

---

## 4. Threat model e raiz de confiança

### 4.1 Ator governado

O threat model mínimo precisa responder:

- qual UID executa o Claude Code;
- se esse UID pode editar `~/.claude/settings.json`;
- se pode remover hooks, alterar plugins ou iniciar outro launcher;
- se pode modificar CI, rulesets ou emitir status checks;
- se possui `sudo` ou acesso administrativo.

A propriedade estrutural é:

\[
policy \in writable(actor) \Rightarrow policy \text{ não é fronteira contra esse ator}.
\]

### 4.2 Estado atual

A política ativa ainda é `governed=user`: os hooks que rodam vivem em `~/.claude`, gravável pelo
ator. O que existe, e o que não existe, precisa ser dito com precisão — porque tanto declarar
demais quanto declarar de menos deixam o leitor sem saber o que falta:

- **existe**: `install/apply-managed.sh`, instalador root-owned que constrói a árvore em uma
  área de staging, aplica posse e modo lá, roda **todos** os portões contra o staging e só então
  publica. Deploy reprovado deixa a árvore ativa byte a byte inalterada (caso MG15);
- **não existe**: a **ativação**. `allowManagedHooksOnly` exige `sudo` e não foi ligado;
- **não existe**: o fechamento da cadeia. Duas dependências continuam no espaço do ator — o
  próprio checkout de onde `apply-managed.sh` é invocado (um script que o ator pode editar antes
  do `sudo`), e `EVIDENCE_GATE_REPO`, que o hook managed de `SessionStart` usa para localizar
  `install/verify.sh`. Um hook root-owned que invoca um verificador vindo do espaço do ator não
  é raiz de confiança:

\[
Hook_{root} + Verifier_{ator} \neq TrustRoot.
\]

Fechar isso exige um bootstrap mínimo e pinado (release com digest conferido, extração em
staging root-owned, rename atômico) e uma verificação managed que rode a partir de `/opt`, sem
voltar ao checkout. Não está implementado.

### 4.3 Fase de raiz gerenciada

A evolução prevista utiliza:

- managed settings;
- `allowManagedHooksOnly`;
- launcher não gravável pelo ator;
- plugins autorizados e pinados;
- policy digest registrado no runtime.

A documentação oficial confirma que `allowManagedHooksOnly` bloqueia hooks de usuário, projeto e plugins não force-enabled, preservando somente hooks gerenciados, SDK hooks e plugins autorizados por política [R3].

---

## 5. Evidence ledger e cache de vereditos

Um registro de evidência deve conter, no mínimo:

```json
{
  "snapshot_digest": "sha256:...",
  "verifier_digest": "sha256:...",
  "environment_digest": "sha256:...",
  "policy_digest": "sha256:...",
  "verdict": "pass|fail|gap",
  "evidence_ref": "sha256:..."
}
```

A chave de reutilização é:

\[
K = H(snapshot, verifier, environment, policy).
\]

A regra de cache é:

```text
cached pass    -> pode ser reutilizado se K coincide
cached fail    -> não vira sucesso; reexecuta ou continua bloqueando
cached gap     -> não é sucesso; reexecuta quando a capacidade existir
cache ausente  -> executa
```

O defeito original gravava carimbo antes do verificador e transformava falha anterior em sucesso posterior. A garantia atual é:

\[
CachedFail(K) \not\Rightarrow Pass(K).
\]

O `environment_digest` inclui caminho real, SHA-256 completo e versão dos executáveis relevantes. Ele ainda não representa imagem hermética, bibliotecas dinâmicas ou toda variável ambiental; essa limitação é declarada.

---

## 6. Contrato científico dos testes

Uma pós-condição verdadeira não prova que a operação ocorreu. Cinco defeitos desta evolução compartilharam a estrutura:

```text
precondição falha
-> operação não executa
-> pós-condição é vacuamente verdadeira
-> teste fica verde
```

O contrato completo adotado é:

\[
Preconditions
\land TreatmentApplied
\land OracleDiscriminating
\land OperationExecuted
\land Postcondition.
\]

### 6.1 Dependência do oráculo versus variação ambiental

| Pré-requisito ausente | Significado | Tratamento |
|---|---|---|
| dependência do oráculo | o teste não foi realizado | `exit 2`, `NOT_VERIFIED` |
| variante ambiental | uma variante não pôde ser exercitada | `SKIP`, com guarda exigindo ao menos uma variante válida |

Exemplo: sem `packaging`, a compatibilidade de `SpecifierSet` não pode ser avaliada. Isso não é `SKIP`; é `NOT_VERIFIED`.

Exemplo: um locale inexistente pode ser ignorado, desde que ao menos um locale com ordenação comprovadamente distinta de `C` seja exercitado.

### 6.2 Contagem invariável

Cada suíte possui `EXPECTED` fixo. Isso impede que um matcher quebrado, fixture ausente ou bloco não executado reduza silenciosamente a cobertura:

\[
ExecutedCases = ExpectedCases.
\]

---

## 7. Estratégias de verificação

### 7.1 Regressão

Cada caso reproduz um mecanismo observado, executa o componente real e exige saída e exit code específicos. Um teste chamado “bug do throttle” só é válido se montar o estado que causava o false-green.

```bash
bash tests/unit/regressao-gate.sh
```

As contagens correntes são publicadas em [`docs/status.generated.md`](docs/status.generated.md).

### 7.2 Mutation testing

Mutation testing avalia a sensibilidade da suíte à remoção deliberada de uma garantia [R4]. Para uma garantia `g` e seu mutante `m_g`:

\[
Test(S \setminus g)=FAIL.
\]

Um mutante só é considerado válido quando:

1. o baseline passa;
2. a transformação foi aplicada;
3. o arquivo mutado permanece sintaticamente válido quando esperado;
4. o teste-alvo falha;
5. a falha é atribuível à propriedade removida.

```bash
bash tests/mutation/run.sh
bash tests/mutation/install.sh
```

### 7.3 Testes metamórficos

Quando não existe um output absoluto conveniente, testa-se uma relação necessária entre execuções [R5].

Para o manifesto:

\[
Manifest(tree,locale_1)=Manifest(tree,locale_2),
\]

desde que os locales sejam comportamentalmente distintos na ordenação sentinela.

```bash
bash tests/unit/reprodutibilidade.sh
```

### 7.4 Property-based testing

É a próxima extensão recomendada para:

- parsers de workflow;
- placeholders;
- paths e filenames hostis;
- manifestos e digests;
- eventos incompletos;
- combinações de estado.

A escolha segue o princípio de maior retorno observado: gerar muitos casos estruturados sem manter uma especificação formal paralela [R6].

### 7.5 Métodos formais

TLA+, Alloy ou model checking não são prioridade automática. Serão considerados quando surgirem defeitos de concorrência, composição de autoridades, races snapshot-evidência ou transições que testes gerativos não cubram adequadamente. O custo de manter especificação e implementação sincronizadas deve ser comparado ao ganho marginal.

---

## 8. Adaptadores de código

Adaptadores são contratos declarativos com:

- extensões aplicáveis;
- `command` e `args[]`;
- dependências;
- efeitos declarados;
- rationale;
- classificação de execução de código do repositório.

Não se usa `sh -c` para compor comandos provenientes de dados não confiáveis.

```json
{
  "exec": {
    "command": "ruff",
    "args": ["check", "--", "$FILES"]
  },
  "declared_effects": {
    "executes_repository_code": false
  }
}
```

Se `executes_repository_code=true`, o adaptador não roda por autodetecção; vira lacuna declarada até existir sandbox ou aprovação apropriada.

A classificação depende da declaração correta. O incidente de `.NET` demonstrou que uma regra não detecta uma classificação falsa; revisão de fonte primária e corpus hostil continuam necessários. A documentação da Microsoft adverte que `dotnet format` pode restaurar, compilar e executar analyzers do projeto [R7].

### Monorepos

Sem override explícito de projeto, todos os adaptadores aplicáveis devem passar:

\[
Candidate(x)=\bigwedge_{a\in Applicable(x)} Pass(a,x).
\]

Um `.claude/verify.json` aprovado constitui override semântico deliberado e substitui os adaptadores genéricos. A documentação não o descreve mais como conjunção universal.

---

## 9. Ferramentas documentais

Os adaptadores de documentos deixaram de ser especificação passiva. O executor:

```text
execution/document-tools/doctool.sh
```

possui três verbos:

```text
probe
plans
run
```

O registry está em:

```text
execution/adapters/documents/*.json
```

### 9.1 Pipeline

```text
arquivo
-> detecção/probe barato
-> classificação da intenção
-> seleção de plano
-> execução limitada
-> normalização
-> evidence pack ancorado
-> injeção seletiva em contexto
```

### 9.2 Princípio de redução

Para um documento com conteúdo total `B` e informação relevante `I`, ferramentas especializadas têm maior retorno quando:

\[
\frac{I}{B}\ll 1.
\]

Exemplos:

- PDF: localizar termos antes de renderizar páginas;
- planilha: `shape`, tipos, nulos e agregações antes de linhas;
- Office: preservar títulos e tabelas antes de resumir;
- mídia: declarar lacuna quando OCR/transcrição não está disponível.

### 9.3 Evidence pack

```json
{
  "artifact_digest": "sha256:...",
  "adapter": "pdf",
  "plan": "text-search",
  "untrusted": true,
  "claims": [
    {
      "excerpt": "...",
      "anchor": {"page": 14, "line": 320}
    }
  ],
  "gaps": [],
  "cost": {"bytes_emitted": 3120, "elapsed_ms": 870}
}
```

Invariantes:

- conteúdo documental é dado, nunca política;
- todo excerto é marcado `untrusted`;
- todo resultado possui digest e âncora;
- lacunas são explícitas;
- filenames hostis não viram shell;
- há timeout e teto de bytes.

```bash
bash tests/unit/document-tools.sh
```

### 9.4 Limites atuais

- sem sandbox real;
- sem cache content-addressed;
- sem OCR integrado;
- sem transcrição;
- sem benchmark pareado leitura direta versus pipeline.

---

## 10. Grafos de dependência

Grafos ainda são uma linha exploratória, não uma garantia evidence-grade.

Um grafo válido deve ser definido como:

\[
G_s=(V,E,\tau_V,\tau_E,\pi,s),
\]

onde:

- `V`: nós;
- `E`: arestas;
- `τV`: tipos de nó;
- `τE`: tipos de relação;
- `π`: proveniência e âncoras;
- `s`: snapshot do código.

Toda aresta deve apontar para fonte verificável:

```json
{
  "source": "PaymentService.charge",
  "target": "FraudClient.check",
  "relation": "calls",
  "anchor": {"file": "payments/service.py", "line": 184},
  "extractor": "python-ast",
  "snapshot": "sha256:..."
}
```

Métricas previstas:

\[
Precision=\frac{TP}{TP+FP},
\qquad
Recall=\frac{TP}{TP+FN}.
\]

Para análise de impacto:

\[
ImpactFNR=\frac{FN}{TP+FN}.
\]

O grafo deve ser comparado a baselines:

```text
source + rg
source + LSP
graph
LSP + graph
```

O projeto não assume que grafos dominam LSP ou busca textual. O valor precisa ser medido por recall, precisão, custo, latência e taxa de staleness.

---

## 11. Skills, personas e subagentes

### 11.1 Personas

O estudo de Zheng et al. avaliou 162 personas e 2.410 questões, sem ganho médio confiável frente ao controle; os efeitos variaram por papel e domínio [R8]. Personas persistentes não são default.

Preferimos checklists operacionais:

```text
liste premissas
busque contraexemplos
separe necessidade de suficiência
registre o não verificado
```

em vez de papéis vagos como “aja como epistemólogo”.

### 11.2 Skills

O SWE-Skills-Bench reporta ganho médio pequeno, muitos deltas nulos, alguns ganhos especializados e regressões por incompatibilidade de versão [R9]. O SkillLearnBench mostra que feedback externo pode produzir melhoria, enquanto self-feedback isolado favorece recursive drift [R10].

Consequências:

- skills não são promovidas por intuição;
- precisam ser específicas e version-aware;
- skills geradas entram em quarentena;
- promoção exige avaliação pareada;
- documentação autoritativa pode virar cápsula temporária, não skill permanente.

### 11.3 Subagentes

Subagentes são partições de contexto, ferramentas, orçamento e autoridade. Não são usados apenas para paralelismo. Devem ser acionados quando houver sinal distinto, grande volume isolável, ferramenta específica ou unidade realmente paralelizável.

O contrato de subagente é testado sob locales distintos para impedir rejeição indevida de retornos acentuados. O estado e as contagens correntes são derivados por `scripts/status.sh`.

---

## 12. Segurança e supply chain

A CI verifica:

- actions pinadas por SHA completo;
- pacotes Python com versão exata;
- runner nomeado, não `-latest`;
- exceções de `apt` documentadas;
- compatibilidade entre requisitos dos adaptadores e versões instaladas;
- dependências dos próprios oráculos.

```bash
bash tests/unit/supply-chain.sh
```

A documentação do GitHub recomenda pinagem por SHA completo para actions imutáveis [R11].

`ubuntu-24.04` e o registro de versões fornecem **auditabilidade**, não hermeticidade. O estado futuro desejado é uma imagem por digest:

```text
container@sha256:<digest>
```

com SBOM e digest incluídos no evidence ledger.

---

## 13. CI e enforcement

O workflow executa:

```text
sintaxe
contratos de adaptadores
manifesto
status gerado
supply chain
document tools
metamorfismo
raiz de confiança (prefixo de ensaio)
propriedades
claim ledger
concorrência
regressão
mutação do gate
mutação do contrato de subagente
mutação do instalador
suíte legada
```

```bash
# execução local equivalente. Uma por vez: as suítes não são reentrantes entre si,
# e o lock em tests/lib/lock.sh reprova com exit 3 se houver corrida.
bash tests/unit/supply-chain.sh
bash tests/unit/document-tools.sh
bash tests/unit/reprodutibilidade.sh
bash tests/unit/fronteira-externa.sh
bash tests/unit/managed.sh
bash tests/unit/propriedades.sh
bash tests/unit/claims.sh
bash tests/unit/concorrencia.sh
bash tests/unit/regressao-gate.sh
bash tests/mutation/run.sh
bash tests/mutation/contrato.sh
bash tests/mutation/install.sh
bash tests/mutation/fronteira.sh
bash tests/unit/run.sh
bash scripts/status.sh --check
bash install/verify.sh
```

### O workflow passou a ser gate — e isso foi medido

Desde 2026-08-04 há um ruleset ativo sobre o branch default com `bypass_actors` vazio,
exigindo pull request e o status check `verify`. A distinção que este projeto insiste em
fazer: **ter criado o ruleset não é enforcement; enforcement é o push recusado.**

```console
$ git push origin fase1/contrato-ancora:main
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
remote: - Required status check "verify" is expected.
 ! [remote rejected] fase1/contrato-ancora -> main (push declined due to repository rule violations)
exit=1        # origin/main permaneceu em 92908d1
```

O push partiu do token com `admin: true` — o ator governado em sua maior autoridade sobre o
repositório — e foi recusado. Em rulesets o bypass só existe por concessão explícita, ao
contrário da branch protection clássica, onde ignorar administradores é uma flag.

**Precisão da afirmação, obtida por um segundo teste.** Ao reconferir no fim da sessão, um push
direto foi *aceito* — e o controle mostrou por quê: o SHA empurrado já era o head de um PR com
os required checks verdes, e o GitHub registrou a operação como `state: MERGED`. Empurrar um
SHA que já satisfaz todos os requisitos é cumprir a política, não contorná-la. Com um commit
novo e nenhum PR, a recusa se repete (`GH013`, exit 1, `main` inalterado).

Logo a formulação correta não é "push direto falha", e sim: **um artefato que não passou por PR
com os required checks verdes não chega a `main`.** Sem o controle, a primeira observação teria
produzido uma refutação falsa de uma garantia verdadeira — o erro simétrico do que este projeto
persegue, e igualmente caro.

**O limite, que continua valendo:** quem tem `admin` pode *desativar* o ruleset. O que está
provado é que não há bypass *dentro* da regra, não que a regra seja irremovível. Desativar
deixa rastro no audit log; contornar em silêncio não deixaria — e essa diferença é todo o
alcance possível sem uma autoridade organizacional acima do dono do repositório.

Registro completo em
[`evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`](evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md).

---

## 14. Instalação e conformidade

```bash
bash install/manifest.sh
bash install/apply.sh --dry-run
bash install/apply.sh
bash install/verify.sh
```

### 14.1 Invariantes

Manifesto como autoridade:

\[
Installed = DesiredManifest.
\]

Dry-run não destrutivo:

\[
DRY=1 \Rightarrow State_{after}=State_{before}.
\]

Convergência segura:

- remove apenas caminhos registrados em `managed-files.lock`;
- não remove arquivos desconhecidos;
- separa `REPO-DRIFT` de drift da instalação.

### 14.2 Liveness

`SessionStart` grava heartbeat quando o hook executa e ultrapassa suas precondições.

\[
HeartbeatPresent \Rightarrow HookExecuted.
\]

Mas:

\[
HeartbeatAbsent \not\Rightarrow Drift.
\]

Ausência também pode significar observador morto. A confirmação do runtime exige `/hooks`, `--debug` e, futuramente, raiz gerenciada.

---

## 15. Protocolo científico de evolução

Para cada defeito ou proposta:

1. formular a claim;
2. definir condição de refutação;
3. reproduzir antes de corrigir;
4. implementar a menor correção estrutural;
5. criar regressão;
6. criar mutante ou transformação negativa;
7. executar em ambiente distinto;
8. registrar escopo e limitações.

O registro de claims **existe** — `evidence/claims/`, 16 alegações, validadas por
`evidence/validate-claims.py` e exercitadas por `tests/unit/claims.sh`. O schema é o v2:

```yaml
claim_id: C-001
claim: "Falha em cache nunca é reutilizada como sucesso."
type: empirical-invariant
scope:
  subject_snapshot: "<sha de 40 hex>"   # o commit do ARTEFATO avaliado
  platforms: [local-linux, github-ubuntu-24.04]
  runtime: {claude_code: 2.1.220}       # opcional: versão do sistema observado
evidence:
  regression: [G1]                      # resolvido contra o subject_snapshot
  mutants: [M1]
  observation:                          # quando o lastro é uma medição registrada
    command: "..."
    recorded: evidence/observations/<arquivo>.md
    blob_sha: "<sha de 40 hex do CONTEÚDO>"
    line_start: 48
    line_end: 76
  ci: {run_id: 30924006484, head_sha: "<sha de 40 hex>", workflow: verify-pr}
warrant: "O mutante que remove a distinção fail/pass é morto por G1."
limitations:
  - "Não é prova universal."
status: supported-in-tested-domain
```

**Por que `blob_sha`, e não `(caminho, commit)`.** O v1 ancorava a evidência no *nome* do
arquivo dentro de um snapshot, e conferia `git cat-file -e <commit>:<caminho>` — que o arquivo
existia. Uma auditoria externa encontrou o furo em C-016: o arquivo existia no snapshot
declarado, o **conteúdo citado** não; ele fora ampliado depois, e o validador aprovava. Um nome
pode passar a designar outro conteúdo; um endereço content-addressed não pode. Reproduzido em
`tests/unit/claims.sh`, caso L13, com controle positivo ao lado.

Não existe campo `claim_revision`: o SHA do commit que *contém* a claim não existe enquanto ela
está sendo escrita, e um campo auto-declarado seria mais fraco que `git log --follow` sobre o
próprio arquivo. É também por isso que a evidência ancora em blob e não em commit — o blob é
calculável antes do commit.

---

## 16. Avaliação estatística futura

### 16.1 Unidade experimental

\[
u=(task,repo\_snapshot,environment,model,runtime,seed).
\]

### 16.2 Primeiro contraste

```text
A: Claude Code baseline
B: harness mínimo evidence-gated
```

Sem personas, grafos ou skills adicionais, para isolar o núcleo.

### 16.3 Métricas seletivas

Unsafe acceptance rate:

\[
UAR=P(ACCEPT\mid external\ fail).
\]

Unnecessary rejection rate:

\[
URR=P(REJECT\mid external\ pass).
\]

Abstention rate:

\[
AR=P(ABSTAIN).
\]

Verified yield:

\[
VY=P(ACCEPT\land external\ pass).
\]

Coverage:

\[
Coverage=P(non\text{-}abstain).
\]

Otimização proposta:

\[
\max VY
\]

sujeito a:

\[
UAR\leq\alpha,\quad URR\leq\beta,\quad AR\leq\gamma,
\]

\[
security\_violations=0,
\quad snapshot\_mismatch=0.
\]

### 16.4 Pares discordantes

Para baseline e tratamento pareados:

- `n01`: baseline falha, tratamento passa;
- `n10`: baseline passa, tratamento falha.

Efeito líquido:

\[
d=\frac{n_{01}-n_{10}}{n}.
\]

Discordância:

\[
q=\frac{n_{01}+n_{10}}{n}.
\]

McNemar usa os pares discordantes [R13]. Para múltiplos repositórios e repetições, serão usados bootstrap estratificado e modelo logístico hierárquico [R14].

---

## 17. Maturidade atual

| Nível | Descrição | Estado |
|---|---|---|
| M0 | narrativa sem mecanismo | superado |
| M1 | mecanismo executável | superado |
| M2 | regressão, mutação, metamorfismo e CI ambientalmente independente | **atingido** |
| M3 | enforcement, managed policy, sandbox e runtime confirmado | **parcial** — ver decomposição |
| M4 | eficácia medida em corpus congelado | pendente |
| M5 | auditoria adversarial recorrente e garantias formais seletivas | pendente |

M3 é composto, e tratá-lo como um único bit esconderia exatamente o que falta:

| Componente de M3 | Estado | Base |
|---|---|---|
| enforcement na fronteira externa | **atingido** | push do admin recusado (GH013), medido; contexto exigido é único desde a separação `verify-pr`/`verify-push` |
| runtime confirmado | **atingido** | precedência de hooks medida; bloqueio E2E de `PreToolUse` e `SubagentStop` observado contra o binário |
| managed policy | **construído, não ativado** | instalador com 53 asserções contra prefixo de ensaio, deploy em staging com publicação após os portões; `allowManagedHooksOnly` exige `sudo` e não foi ativado |
| sandbox | **não iniciado** | parsers de documento seguem com a autoridade do usuário |
| cadeia local fora do ator | **não atingido** | o hook managed de `SessionStart` usa `EVIDENCE_GATE_REPO`, que aponta para o checkout — gravável pelo ator. Hook root-owned invocando verificador do espaço do ator não é raiz de confiança |

Classificação atual:

> **Protótipo experimental robusto, mecanicamente verificável e ambientalmente reproduzido, com fronteira externa que comprovadamente impõe. Ainda não é trust boundary local — a política continua gravável pelo ator —, não é hermético, não possui sandbox, não tem validação estatística de eficácia e não passou por auditoria autoralmente independente.**

---

## 18. Roadmap

### P0 — validade operacional — **fechado**

- ~~validar `/hooks`, `--debug` e `/status`~~ — medido por `--include-hook-events`, observável
  mais forte que `/hooks`: mostra o que **executou**, não o que está configurado;
- ~~criar claim ledger~~ — `evidence/claims/`, com validador que resolve toda referência
  contra a suíte;
- ~~base de comparação sem upstream~~ — G12, com mutante M10;
- ~~property-based testing~~ — `tests/unit/propriedades.sh`, que encontrou dois detectores de
  segurança furados na primeira execução;
- manter o status documental gerado automaticamente.

### P1 — enforcement — **fechado e medido**

- required status check `verify-pr` (contexto único; `verify-push` roda a mesma verificação
  em `push` e **não** deve ser exigido);
- ruleset com `bypass_actors` vazio;
- `strict_required_status_checks_policy`, exigindo a branch atualizada com a base.

Verificar depois de qualquer alteração:

```bash
gh api repos/<owner>/<repo>/rulesets --jq '.[] | {name, enforcement}'
git push origin <branch>:main    # precisa ser recusado com GH013
```

### P2 — raiz de confiança

- managed settings;
- `allowManagedHooksOnly`;
- launcher não gravável;
- plugins pinados e autorizados.

### P3 — hardening

- sandbox (**a maior lacuna aberta**: parsers de documento rodam com a
  autoridade do usuário);
- container por digest e lock de dependências com hashes;
- CI executa cada suíte UMA vez, com o status agregado a partir de artifacts em vez de
  reexecutar o experimento inteiro;
- digest transitivo dos bytes que `.claude/verify.json` manda executar.

Os itens *base para commits sem upstream* e *property-based testing* estavam repetidos aqui
depois de P0 já os declarar fechados — duas cópias da mesma verdade, que é o defeito que este
repositório persegue. Removidos daqui; permanecem em P0, com a evidência.

### P4 — ciência de eficácia

- corpus congelado;
- testes ocultos;
- seeds e repetições;
- power analysis;
- modelo hierárquico;
- auditoria independente.

### P5 — grafos e foundry

- grafo incremental vinculado ao snapshot;
- benchmark contra `rg` e LSP;
- skill foundry em quarentena;
- promoção apenas por evidência.

---

## 19. Estrutura do repositório

```text
control/      política e integridade
execution/    hooks, adaptadores, agents, skills, document-tools
evidence/     gate, ledger e telemetria
install/      manifesto, apply, verify e lock de gerenciados
scripts/      geração e validação do status documental
tests/unit/   regressão, metamorfismo, supply-chain e legado
tests/mutation/ mutation testing do gate, instalador e fronteira externa
docs/adr/     decisões, contraexemplos e limites
.github/      verificação remota
```

---

## 20. Referências

### Claude Code e GitHub

- **[R1]** Anthropic. *Claude Code documentation*. https://code.claude.com/docs/
- **[R2]** Anthropic. *Hooks reference: Stop, StopFailure, TaskCompleted, ConfigChange and exit semantics*. https://code.claude.com/docs/en/hooks
- **[R3]** Anthropic. *Claude Code settings: managed settings and allowManagedHooksOnly*. https://code.claude.com/docs/en/settings
- **[R11]** GitHub. *Security hardening for GitHub Actions — pinning actions to a full-length commit SHA*. https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions
- **[R12]** GitHub. *Required status checks, protected branches and rulesets*. https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets

### Teste de software e estatística

- **[R4]** Jia, Y.; Harman, M. “An Analysis and Survey of the Development of Mutation Testing.” *IEEE Transactions on Software Engineering*, 37(5), 2011. DOI: https://doi.org/10.1109/TSE.2010.62
- **[R5]** Chen, T. Y.; Cheung, S. C.; Yiu, S. M. “Metamorphic Testing: A New Approach for Generating Next Test Cases.” https://arxiv.org/abs/2002.12543
- **[R6]** Claessen, K.; Hughes, J. “QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs.” ICFP 2000. https://doi.org/10.1145/351240.351266
- **[R13]** McNemar, Q. “Note on the Sampling Error of the Difference Between Correlated Proportions or Percentages.” *Psychometrika*, 12, 1947. https://doi.org/10.1007/BF02295996
- **[R14]** Efron, B.; Tibshirani, R. J. *An Introduction to the Bootstrap*. Chapman & Hall/CRC, 1993. https://doi.org/10.1007/978-1-4899-4541-9

### Agentes, personas e skills

- **[R8]** Zheng, M. et al. “When ‘A Helpful Assistant’ Is Not Really Helpful: Personas in System Prompts Do Not Improve Performances of Large Language Models.” https://arxiv.org/abs/2311.10054
- **[R9]** Han, T. et al. “SWE-Skills-Bench: Do Agent Skills Actually Help in Real-World Software Engineering?” https://arxiv.org/abs/2603.15401 — repositório: https://github.com/GeniusHTX/SWE-Skills-Bench
- **[R10]** Zhong, S. et al. “SkillLearnBench: Benchmarking Continual Learning Methods for Agent Skill Generation on Real-World Tasks.” https://arxiv.org/abs/2604.20087 — repositório: https://github.com/cxcscmu/SkillLearnBench

### Ferramentas e segurança

- **[R7]** Microsoft. *dotnet format documentation and security caution*. https://learn.microsoft.com/dotnet/core/tools/dotnet-format
- OWASP. *Top 10 for Large Language Model Applications*. https://owasp.org/www-project-top-10-for-large-language-model-applications/
- NIST. *AI Risk Management Framework*. https://www.nist.gov/itl/ai-risk-management-framework
- SLSA. *Supply-chain Levels for Software Artifacts*. https://slsa.dev/
- in-toto. *A framework to secure the integrity of software supply chains*. https://in-toto.io/

---

## 21. Limites declarados

- a política ainda é gravável pelo ator — `install/apply-managed.sh` existe e foi exercitado
  contra prefixo de ensaio (53 asserções), mas `allowManagedHooksOnly` **não foi ativado**:
  exige `sudo` com senha. Que o runtime honre a flag é, hoje, **não verificado**;
- o ambiente é auditável, não hermético;
- comandos do repositório ainda exigem sandbox real. Esta é a lacuna aberta mais relevante, e
  ela deve travar a expansão para OCR e novos formatos até haver isolamento;
- grafos não foram avaliados;
- eficácia externa não foi medida;
- telemetria longitudinal está incompleta;
- não há auditoria autoralmente independente;
- o ruleset **impõe**, mas quem tem `admin` pode desativá-lo: o provado é a ausência de bypass
  dentro da regra, não a irremovibilidade da regra.

Estas limitações não são notas laterais. Elas delimitam exatamente o que o projeto pode afirmar.

### Deixaram de ser limites em 2026-08-04

Limite resolvido que continua escrito é a mesma classe de drift que originou este projeto.
Estes saem da lista, mas com o rastro de onde está a medição — do contrário o leitor não
distingue "resolvido" de "apagado".

| Era limite | Estado agora | Onde está a evidência |
|---|---|---|
| precedência runtime de hooks/plugins não confirmada | **medida**: hooks de plugin somam aos de usuário, não sobrepõem | [`evidence/observations/2026-08-04-precedencia-de-hooks.md`](evidence/observations/2026-08-04-precedencia-de-hooks.md) |
| a CI depende de ruleset para virar enforcement | **impõe**: push direto do admin recusado com GH013 | [`evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`](evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md) |
| commits locais sem upstream precisam de base explícita | **corrigido** (G12), com mutante M10 | `evidence/hooks/verify-gate.sh`, `tests/unit/regressao-gate.sh` |

### Claim ledger

As afirmações verificáveis deste repositório estão em [`evidence/claims/`](evidence/claims/),
uma por arquivo, com escopo, garantia (`warrant`), contraexemplos e limites. O validador
`evidence/validate-claims.py` **resolve toda referência de evidência contra a suíte real**:
citar uma regressão ou um mutante que não existe reprova. O inventário é derivado de `tests/`
a cada execução, nunca digitado — uma lista mantida à mão seria uma segunda cópia da verdade.

---

## 22. Regra de contribuição

Toda nova garantia deve incluir:

1. claim explícita;
2. fonte ou rationale;
3. contraexemplo reproduzível quando aplicável;
4. teste de regressão;
5. teste negativo ou mutante;
6. precondições do oráculo;
7. escopo e limitações;
8. execução em CI.

A regra final é:

> Uma regra que depende de o autor lembrar de aplicá-la é uma expectativa. Ela se torna garantia somente quando sua violação produz automaticamente um sinal observável, atribuível e vinculado ao estado correto.
