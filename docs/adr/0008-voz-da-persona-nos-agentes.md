# ADR 0008 - Voz da persona nos agentes (fronteira produto-vs-analise)

- Data: 2026-07-01
- Status: Aceito
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0002 (reforma da persona), 0004 (colegiado visivel); I.2, I.2.4.3, Diretriz 1, Diretriz 7.2

## Contexto

A configuracao original (ADR 0002; guardrail I.2.4.3; Diretriz 1) proibia a voz da persona em
TODO artefato, incluindo os system prompts dos agentes - a neutralidade era definida por "arquivo".
Pedido do usuario: os agentes devem CARREGAR a persona e os rotulos de voz (ex.: `[Auditor]`,
`[Diretor de Arte]`), num registro formal-analitico. E requisito (autoridade do usuario sobre o
que construir), nao fato tecnico falseavel - portanto acata-se e atualiza-se a regra.

## Decisao

Redesenhar a fronteira da neutralidade pelo criterio PRODUTO-DURAVEL vs ANALISE, nao por "arquivo":

- **Voz PERMITIDA (canais de raciocinio):** prosa de chat ao usuario; system prompt dos agentes
  (`agents/*.md`); e o retorno analitico do agente ao orquestrador (RESULTADO/EVIDENCIA/...).
- **Voz PROIBIDA (invariante preservado):** o PRODUTO duravel que a sessao entrega em arquivo -
  codigo, comentarios, mensagens de commit, corpo de PR, docs de feature, ADRs, strings de log/erro,
  nomes de teste. Permanecem neutros e profissionais.
- **Prompt de delegacao:** o CONTRATO (PRD/grafo/evidencia/escopo) permanece preciso e completo;
  a voz pode enquadrar, nunca substituir o contrato.
- **Distinto e transversal:** o lexico de HYPE/BAJULACAO e o EMOJI seguem proibidos em TODO
  artefato, inclusive nos agentes. A mudanca libera a VOZ (rotulos, contraditorio, registro
  erudito-analitico), nao a bajulacao nem o emoji.

## Racional

O objetivo original da neutralidade era o produto profissional (commit/PR/doc/codigo), nao o
raciocinio. A voz e uma camada de ANALISE; move-la para os agentes enriquece o contraditorio
(cada agente arrazoa com a sua lente rotulada) sem contaminar o entregavel. O registro dos agentes
eleva-se a formal-analitico (premissa explicita, falseabilidade, terminologia exata), sujeito a
mesma trava de anti-falso-rigor: a voz serve o argumento, nunca o substitui (I.2.4.1); erudicao
ornamental que nao muda uma conclusao e o falso rigor que a Diretriz 3.1 condena.

## Limites honestos

- O hook nao distingue voz de neutralidade; ele barra emoji (todo arquivo) e lexico proibido (fora
  de `.claude/`). A neutralidade do PRODUTO duravel (commit via Bash, codigo, doc) e disciplina do
  agente - instruido a manter suas saidas de arquivo neutras -, nao garantia mecanica.
- Voz em excesso no agente e risco de falso rigor retorico; cada agente mantem a proporcionalidade
  (voz curta onde o problema e menor) e a trava "a lente cede a vez se nao tem o que dizer".

## Validacao

Guardrails revisados (I.2 onde-se-aplica; I.2.4.3; Diretriz 1; Diretriz 7.2). Os 14 agentes sao
refinados com voz + registro formal-analitico sob gate `revisor-critico` por lote, com C-sweep
antes de cada commit. O produto duravel (este ADR inclusive) permanece neutro.
