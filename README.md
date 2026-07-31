# claude-mecanismo

Configuracao para Claude Code construida sobre uma regra: **mecanismo executado, nunca alegacao
escrita.** Este README comeca pelo que foi REFUTADO, porque e isso que o distingue de mais uma
promessa.

---

## O que foi falseado, com repro

O projeto anterior (`claude-colegio-analitico`) implementava as praticas que o mercado vende:
persona de especialistas, colegiado visivel, pipeline de 14 subagentes, gates de disciplina.
Quatro arguicoes adversariais independentes, com contexto separado, produziram 20 achados -
**17 reproduzidos por comando**. O que caiu:

| Pratica vendida como boa | Resultado medido |
|---|---|
| Persona / vozes rotuladas na resposta | **Auto-correcao intrinseca.** Mesmos pesos, mesmo contexto, correlacao 1. Degrada (Huang et al., ICLR 2024). |
| "N agentes revisando = melhor" | **Nao.** Debate sobre o mesmo texto nao introduz informacao nova; equivale a um agente com o mesmo orcamento (Smit et al., ICML 2024). |
| Gate de conclusao escrito no CLAUDE.md | **Nunca disparava.** Opt-in, inerte na maioria dos repos. Descoberto por E2E, nao por leitura. |
| Contrato de retorno dos subagentes | **Lia o transcript errado** - julgava a prosa do orquestrador achando que julgava o subagente. Falso positivo E falso negativo. |
| Hook que "avisa" o modelo por stderr | **Nao chega ao modelo.** `hook_success` com `content` vazio. Dois hooks foram decoracao por versoes inteiras. |
| Auto-deteccao do comando de verificacao | **Dava execucao de comando a qualquer repo clonado.** Classe do CVE-2025-59536 (CVSS 8.7). Quatro repros criaram marcador em disco. |
| Metricas de qualidade da propria config | `"9 de 9 conformes (100%)"` -> n=9, regra de tres: compativel com **67%** real. |

O corpo de evidencia completo esta em [`docs/falseamento/`](docs/falseamento/) - 21 documentos,
cada um com o defeito, o repro e a correcao. **Nao e historico do projeto: e o registro de
falseamento**, e existe para impedir que as mesmas praticas voltem por parecerem boas.

---

## O criterio

Toda decisao responde a uma pergunta (Li, *AI Agents in Depth*, Tabela 10-2):

> **A colaboracao introduz INFORMACAO NOVA que um agente sozinho nao obteria durante a geracao?**

| Modo | Informacao nova? | Efeito |
|---|---|---|
| Reler a propria saida em outro papel | Nao | Inutil ou prejudicial |
| Agentes debatendo o mesmo texto | Nao | Equivale a um agente com o mesmo orcamento |
| Revisor usando resultado de EXECUCAO | **Sim** | Melhora significativa |
| Revisor usando SCREENSHOT renderizado | **Sim** | Melhora significativa |
| Revisor usando FERRAMENTA externa | **Sim** | Melhora significativa |

Lastro conferido na fonte: RLEF ([arXiv:2410.02089](https://arxiv.org/abs/2410.02089)) -
feedback de execucao reduz em uma ordem de grandeza as amostras necessarias; WebGen-Agent
([arXiv:2509.22644](https://arxiv.org/abs/2509.22644)) - feedback visual leva o Claude 3.5
Sonnet de **26.4% para 51.9%**.

**Consequencia:** um agente so existe se tiver fonte de sinal externo. Nunca por "papel".

---

## Tres camadas, separadas por acoplamento

O defeito estrutural do projeto anterior era ter as tres fundidas: 19 mencoes de
`python`/`npm` dentro do hook de verificacao. Num projeto C# ou Java, metade da config ficava
inerte.

### Camada 0 - universal

Funciona em qualquer linguagem, sem alteracao.

| Hook | Garante |
|---|---|
| `fable-guard.sh` | Modelo restrito exige consentimento do usuario; **subagente nunca**. O sentinela precisa pertencer a root - um arquivo que o agente consegue criar nao e consentimento. |
| `artifact-discipline.sh` | Sem emoji em artefato; protege os caminhos de consentimento contra escrita pelo modelo. |
| `subagent-contract.sh` | Subagente fecha com RESULTADO/EVIDENCIA e ancora real. Le `last_assistant_message`, nunca o transcript do pai. |
| `read-budget.sh` | Barra leitura de arquivo grande e midia acima do orcamento, devolvendo a receita (`pdftotext`, `rg` + faixa, `pandas`, `ffmpeg`). |
| `output-budget.sh` | Corta o MEIO de saida grande preservando cabeca, cauda e **toda linha de veredito**. Emite objeto `{stdout,stderr,interrupted}` - string era rejeitada em silencio. |
| `self-mod-audit.sh` | Registra escrita em hooks/settings. **Detecta, nao previne** - prevenir exigiria bloquear a manutencao da config. |
| `subagent-probe.sh` | Captura o payload REAL do runtime. Foi ela que revelou dois defeitos invisiveis por leitura. |

Agente: `refutador` - contexto separado, le o diff cru, prompt de refutacao. **O unico com
evidencia empirica**: 7 execucoes, 17 defeitos reproduzidos.

### Camada 1 - adaptadores de toolchain

O hook **nao conhece linguagem nenhuma**. Le `adapters/*.json`. Suportar um ecossistema novo e
**adicionar um arquivo**.

Cada adaptador separa o que a versao anterior confundia, e a confusao era uma vulnerabilidade:

| Campo | Semantica | Aprovacao |
|---|---|---|
| `analyzer` | Le o codigo como DADO | automatica |
| `test` | **Executa** codigo do repositorio | exige aprovacao de root |

Presentes: `python`, `node`, `go`, `rust`, `dotnet`, `java`. Cada `analyzer` carrega
`porque_nao_executa` - justificativa obrigatoria, verificada pela suite.

### Camada 2 - projeto

Padroes de stack e dominio (`security-patterns.json` com Django/DRF/Temporal, `verify-cmd`)
vivem em `.claude/` do REPO, nunca no global. Exemplos em [`camada2-projeto/`](camada2-projeto/).

---

## As tres regras de metodo, cada uma paga com um defeito

1. **Toda instrucao publicada e EXECUTADA literalmente antes de ser publicada.** Tres
   reincidencias: `~` virando `/root` dentro de `sudo`; `sudo` omitido; `"$HOME"` dentro de
   `sudo sh -c`, que expande no shell de root (`man sudoers`, `env_reset`).
2. **Todo teste de garantia de seguranca e validado por MUTACAO.** Remova a garantia, exija que
   o teste REPROVE. Um teste que sobrevive ao mutante testa outra coisa.
3. **Hook que altera estado do runtime exige E2E contra o BINARIO.** Verifique o que o MODELO
   recebeu, nao o que o hook imprimiu.

**Corolario: verificar o artefato nao e verificar a integracao.** Sintaxe correta, `bash -n`
limpo e fixture proprio passando sao compativeis com um mecanismo completamente inerte.

---

## Honestidade sobre o que este repo NAO tem

- **Nao ha medicao de que ele melhora as respostas.** Isso exigiria conjunto de tarefas com
  gabarito e A/B com e sem. Nao foi feito. Todo ganho de qualidade aqui e **hipotese**.
- **Dos agentes, so o `refutador` tem evidencia** (n=7). Os demais foram removidos justamente
  por nao terem.
- **A suite tem 29 casos sobre 8 hooks** - cobertura baixa, e o numero honesto.
- **Pre-condicao de seguranca:** o agente NAO roda como root e `sudo` pede senha. Em
  devcontainer ou CI como root, as garantias de consentimento **valem zero**.
- **Cobertura do livro de referencia:** ~6 secoes de 10 capitulos. O resto e trabalho pendente,
  nao conhecimento adquirido.

Metricas com `n` pequeno sao reportadas com o `n`. Ver
[`docs/metodo/CONHECIMENTO.md`](docs/metodo/CONHECIMENTO.md), secao 6, onde as ferramentas de
significancia estatistica sao aplicadas contra os proprios numeros deste projeto - e
desqualificam um deles.

---

## Instalacao

```bash
git clone https://github.com/MrSchrodingers/claude-mecanismo
cd claude-mecanismo && bash tests/run.sh      # 29/29 antes de instalar
```

Copie `camada0-universal/` e `camada1-toolchain/` para `~/.claude/`, e use
`settings.json` como referencia. `camada2-projeto/` e exemplo - o conteudo dela pertence ao
`.claude/` de cada repositorio.

Licenca MIT.
