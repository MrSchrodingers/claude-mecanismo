# ADR 0003 - Hook UserPromptSubmit para reforco de saliencia do modo operacional

- Data: 2026-06-17
- Status: Aceito (validado dinamicamente - ver Validacao)
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0002-reforma-persona-colegio-analitico.md (esp. secao 9, "limites honestos")

## Contexto

A reforma do ADR 0002 instalou persona + diretrizes + pipeline no `CLAUDE.md` global. O
usuario observou que persona e pipeline "nao pareciam invocados" em sessoes novas.

Investigacao com evidencia (sem assumir o reporte como fato): o `CLAUDE.md` global ESTA no
disco e e carregado por toda sessao nova da CLI - provado por uma sessao headless (`claude
-p`) que recitou a persona, os 13 agentes e a Diretriz 3.1. Portanto NAO ha falha de
propagacao. A causa do sintoma e o "piso inerente" ja documentado no ADR 0002 (secao 9): um
`CLAUDE.md` e instrucao em prosa que o modelo SEGUE, nao recurso que ATIVA. Dois agravantes:
(a) a persona e deliberadamente discreta (uma voz por padrao, sem rotulo); (b) nos projetos
do usuario, um `./CLAUDE.md` de ~1235 linhas empilha com o global e dilui a saliencia da
secao de persona.

## Decisao

Adicionar um hook `UserPromptSubmit` (`~/.claude/hooks/colegio-operating-mode.sh`, wired em
`settings.json`) que RE-INJETA, a cada prompt, um resumo de alta saliencia do modo
operacional: voz (Colegio, uma voz por padrao, sem bajulacao), disciplina epistemica
(evidencia antes de solucao, Ask-Don't-Tell, nao ceder fato sob pressao), anti-falso-rigor,
e o dever de orquestracao por gatilho. O stdout de um hook UserPromptSubmit e adicionado ao
contexto do turno.

O hook e **fail-open** por construcao: so escreve em stdout e sai 0; sem dependencia de jq;
jamais bloqueia o prompt (so um exit 2 / decision:block bloquearia, e o script nunca faz
isso). Isto o distingue do `artifact-discipline.sh`, que e fail-CLOSED de proposito (uma
guarda de seguranca deve bloquear na duvida; um lembrete jamais deve travar o usuario).

## Distincao honesta (nao repetir o over-claim que a validacao do 0002 puniu)

O hook torna a ENTREGA do lembrete deterministica (mecanismo do harness). A ADESAO do modelo
ao lembrete continua SOFT - nenhum hook forca julgamento semantico (perceber A01, adotar a
voz, decidir delegar). E um salto grande de saliencia/probabilidade de adesao, NAO uma
garantia. O unico mecanismo que de fato bloqueia comportamento e o `artifact-discipline.sh`
(emoji/lexico em arquivo). Coerente com o "piso inerente" do ADR 0002.

## Alternativas consideradas

- So aumentar a saliencia no proprio CLAUDE.md (cabecalho imperativo): continua sendo prosa
  diluivel; nao ataca a causa. Rejeitada como solucao isolada.
- Aceitar como esta: valido se o objetivo fosse so o rigor de substancia; o usuario pediu
  manifestacao mais confiavel. Rejeitada.
- SessionStart em vez de UserPromptSubmit: injetaria uma vez no inicio, voltando a diluir ao
  longo da conversa. UserPromptSubmit re-injeta a cada turno - ataca a diluicao multi-turn.

## Validacao (executada em 2026-06-17)

1. `bash -n` do hook: sintaxe OK. Pipe-test: emite o lembrete, exit 0; sem stdin e com stdin
   invalido tambem exit 0 (fail-open confirmado).
2. `settings.json` e JSON valido; `jq -e` confirma o comando do hook UserPromptSubmit; o
   `PreToolUse` (artifact-discipline) foi preservado.
3. PROVA dinamica: uma sessao headless NOVA (`claude -p`) recebeu a injecao, citou
   literalmente a 1a linha do bloco "MODO OPERACIONAL" e identificou corretamente a origem
   como hook UserPromptSubmit. Logo o hook dispara em sessao nova e a injecao chega ao modelo.

## Custos e riscos

- Custo: o resumo (conciso) e injetado a cada turno - some tokens por turno. Aceito pelo
  usuario como troca pela saliencia.
- Risco: o modelo pode aprender a ignorar boilerplate repetido (saliencia decai). A OBSERVAR
  em uso real; se ocorrer, variar/encurtar o lembrete ou condiciona-lo.
- Superficie: vale para a CLI (le ~/.claude). Desktop/web/IDE nao executam este hook.

## Corroboracao empirica (2026-06-23, ref: docs/research/referencias-pesquisa-agentes-llm.md)

- Perda de adesao no MEIO de contexto longo (U-curve, ~25pp): Liu et al., Lost in the Middle (TACL 2024, peer-reviewed).
- ISR colapsa acima de ~6000 palavras: AgentIF (arXiv:2505.16944). Sustentam reinjetar por turno um resumo CURTO de alta saliencia em vez de confiar na diretriz enterrada.
- Reinjecao de plano/subgoal reduz drift: Plan Verification via Reinjecao (arXiv:2509.02761); Subgoal-Driven (arXiv:2603.19685, 6.4%->43%).
