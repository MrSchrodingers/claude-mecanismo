# ADR 0015 - Arguicao independente da v2: 12 achados e o que eles provam sobre o metodo

- Data: 2026-07-31
- Status: aceito
- Corrige: 0011 (numeros e justificativa), 0012 (garantia do Fable), 0014 (o Achado 1)

## Contexto

A v2 foi projetada, implementada, justificada e declarada verificada pela MESMA sessao. O
ADR 0011 reconhecia o risco em abstrato, mas nao o tratou: nao houve arguicao independente.

Este ADR registra o resultado de submeter a reforma ao agente `refutador` - contexto separado,
lendo o `git diff c9be8b3..HEAD` cru e executando os hooks, sem ver o contexto do autor.

**Veredito emitido: revisar-e-ressubmeter.** Doze achados. A tese sobrevive; a entrega falhou.
Custo da arguicao: 301.408 tokens de subagente, 107 chamadas de ferramenta, ~29 min.

## Por que o resultado importa mais que os achados

Os achados 1 a 4 - os quatro mais graves - **so existem porque o contexto era separado**.
Nenhum deles e encontravel por releitura: todos exigiram EXECUTAR o hook e observar o
comportamento divergir da documentacao. E a Tabela 10-2 (Li, *AI Agents in Depth*) instanciada
sobre o proprio sistema que a implementa: revisao sem informacao nova nao melhora nada;
revisao com resultado de execucao melhora.

O caso mais nitido: o `subagent-contract.sh` **barrou o refutador indevidamente**, e a
mensagem de bloqueio foi a evidencia que o levou ao defeito. O mecanismo defeituoso denunciou
a si mesmo ao ser exercitado - e destruiu a entrega do relatorio no processo.

## O padrao que os 12 achados revelam

Tres mecanismos foram publicados como garantia e depois encontrados quebrados - `verify-gate`,
`subagent-contract`, `fable-guard`. **Mesma causa nos tres:** o autor verificou o ARTEFATO
(sintaxe, `bash -n`, fixture que ele mesmo escreveu) e chamou de verificado. O que falhava era
a INTEGRACAO com o runtime real.

Regras adotadas, que sao a resposta estrutural:

1. **Hook novo so entra com um evento REAL capturado como fixture.** A sonda
   `subagent-probe.sh` deixa de ser temporaria e vira componente permanente - foi ela que
   tornou visivel o defeito do Achado 1.
2. **Toda contagem de passes vira harness commitado** (`tests/run.sh`, ligado ao
   `.claude/verify-cmd`). "16/16" sem harness e auto-avaliacao, pelo proprio C3.
3. **Todo numero publicado vira script** (`scripts/medir-contexto.sh`).
4. **Ausencia numa amostra nao e impossibilidade.** Ver o erro de inferencia abaixo.

## Erro de inferencia do ORQUESTRADOR, registrado

Afirmei que `agent_type` vinha vazio no `SubagentStop`, "logo o matcher nunca casa e o hook e
inerte". Falso. Distribuicao real: 45 vazios, 1 `general-purpose`, 2 `refutador` - e os 45
vazios sao outra CLASSE de evento. Agreguei classes distintas, li ausencia numa amostra
enviesada como impossibilidade estrutural, e contei 2 de 48 como zero.

O refutador tambem se autocorrigiu duas vezes (o matcher dispara; `axe` e alcancavel via
`npx --yes`). Ambos os lados erraram por inferencia a partir de amostra, e ambos corrigiram
por execucao. E a mesma licao nas duas direcoes.

## Os 12 achados e o desfecho

| # | Achado | Desfecho |
|---|---|---|
| 1 | `subagent-contract.sh` lia `.transcript_path` (o do PAI). Falso positivo E falso negativo | CORRIGIDO (ADR 0014). Fonte: `last_assistant_message` -> `agent_transcript_path`. F2P com payload real |
| 2 | Consentimento do Fable **forjavel via Bash** (`artifact-discipline` so cobre Write/Edit) | CORRIGIDO. Bloqueio das rotas de escrita por Bash + sentinela **obrigatoriamente de root** (`sudo` pede senha neste ambiente, logo fora do alcance do agente) |
| 3 | `verify-gate` com 2 bypasses: throttle temporal de 300s, e commitar desligava o gate | CORRIGIDO. Throttle passa a incluir hash do conteudo; deteccao inclui commits nao publicados |
| 4 | Gate inerte no proprio repo da config (`.sh` fora da lista; sem `verify-cmd`) | CORRIGIDO. `.sh/.bash/.zsh` incluidos; `.claude/verify-cmd` -> `bash tests/run.sh` |
| 5 | "Read-only" declarado nao e enforcado (Write disponivel apesar do `tools:`) | DOCUMENTADO nos 4 agentes de revisao: read-only e CONTRATO, nao sandbox. Causa nao isolada |
| 6 | "-79%" nao reproduzivel; baseline e endpoint com escopos diferentes | CORRIGIDO. `scripts/medir-contexto.sh` deriva **-74%** no escopo comparavel; plugin medido a parte |
| 7 | `continuidade` removido alegando que deadcode "e mecanizavel por hook" - `ruff` nao resolve nomes entre modulos | CORRIGIDO. `mypy` no `poka-yoke-lint.sh` fecha a lacuna (`has no attribute` / `is not defined`), com F2P e controle negativo no harness |
| 8 | `revisor-frontend` mandava usar MCP que o proprio `tools:` exclui | CORRIGIDO. Instrucao passa a ser Bash + `npx`; MCP fica com o orquestrador |
| 9 | Referencia morta a `/direcao-de-arte` em `risk-trigger.sh` | CORRIGIDO |
| 10 | Duas citacoes nao verificadas | RESOLVIDO. A de acessibilidade EXISTE - Calo e Gurita, CHI EA 2026, DOI 10.1145/3772363.3799364 (esta na ACM, nao no arXiv, por isso o refutador nao a localizou). A outra e o PDF local que o usuario forneceu |
| 11 | "16/16" nao reproduzivel, sem harness commitado | CORRIGIDO. `tests/run.sh` commitado e ligado ao `verify-cmd` |
| 12 | Sonda de instrumentacao ligada sem prazo; drift live-vs-repo | RESOLVIDO. Sonda promovida a permanente com rotacao de 2 MB e nota de privacidade; `hooks.json` do plugin re-sincronizado |

## O que continua NAO verificado

- Nenhum agente lastreado em ferramenta (`auditor-seguranca`, `revisor-frontend`,
  `analista-otimalidade`) foi executado sobre um diff de projeto real. Sabe-se que os comandos
  existem e funcionam; nao se sabe como o agente se comporta com eles em campo.
- O falso NEGATIVO do `subagent-contract` antigo nao foi quantificado, so demonstrado possivel.
- A causa da divergencia `tools:` vs capacidade efetiva (achado 5) nao foi isolada.
- **Nao ha medicao de que a qualidade das respostas melhorou.** Segue hipotese.

## Conclusao honesta sobre o veredito

O refutador emitiu **revisar-e-ressubmeter**, nao "aprovar". Os 12 achados foram tratados e
a suite passa, mas quem declara o desfecho final nao pode ser o autor - seria repetir
exatamente o erro que originou este ADR. O estado correto e: **corrigido e re-submetido**,
pendente de nova arguicao independente sobre o novo diff.
