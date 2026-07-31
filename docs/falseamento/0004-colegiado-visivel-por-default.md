# ADR 0004 - Colegiado visivel por default (reversao do discriminador estreito)

- Data: 2026-06-17
- Status: Aceito (validado dinamicamente)
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0002 (discriminador estreito, achado 9) e 0003 (hook de saliencia)

## Contexto

O usuario relatou repetidamente que a persona e os especialistas "nao apareciam" ("muito
raramente aparece um [especialista]", "nem efeito tem", "muito superficial, sem o colegiado").

Investigacao com evidencia (sem aceitar nem o reporte nem a minha conclusao anterior como
fato): uma sessao headless executada DE DENTRO de um projeto `debthub-wt` (com `./CLAUDE.md`
de 1235 linhas) confirmou que (a) o `CLAUDE.md` global carrega ali tambem - a sessao
descreveu o Colegio Analitico; (b) o hook UserPromptSubmit dispara naquele diretorio. O
`.claude/` do projeto NAO tem `disableAllHooks` nem `claudeMdExcludes`. Logo: NAO ha falha de
propagacao, NAO ha sobreposicao de repo - global e projeto empilham, ambos carregam.

A causa real do sintoma: o DISCRIMINADOR ESTREITO (ADR 0002 decisao #2, endurecido na
validacao - achado 9 e cetico NOVO-2) tornava UMA voz o default e reservava o colegiado
multi-voz a "tensao real entre lentes". O hook do ADR 0003 REFORCAVA essa supressao a cada
turno. O efeito existia, mas apontado para suprimir os especialistas - exatamente o oposto do
que o usuario quer ver.

## Decisao

Inverter o default: COLEGIADO VISIVEL. Em TODA resposta de conteudo tecnico ou de design,
convocar e ROTULAR as vozes-especialistas pertinentes ([Logico-Epistemologo], [Arquiteto],
[Auditor], [Eng. de Producao], [Analista de Dados]) e mostrar o contraditorio (tese ->
objecao -> replica -> sintese); minimo 2 vozes rotuladas. Voz unica sem rotulo fica SO para
conversa trivial. A proporcionalidade ao risco passa a regular a PROFUNDIDADE do debate, nao
SE as vozes aparecem.

Implementado em: CLAUDE.md I.2 (abertura) + I.2.3 (mecanica) reescritos; o hook
`colegio-operating-mode.sh` reescrito para LIDERAR com a "INSTRUCAO DE FORMA" (responder como
o colegiado), maximizando a saliencia por turno.

## Correcao de requisito vs fato (Diretriz 3)

Isto e correcao de REQUISITO, nao pressao sobre fato tecnico: o usuario e a autoridade sobre o
que construir, e quer o colegiado visivel. Acatado. Trade-off registrado uma vez (afirmacao
mista, sem entrincheirar): colegiado-por-default e mais verboso, e a validacao do ADR 0002
marcou multi-voz forcado como risco de "teatro"/falso rigor. A escolha do usuario prevalece;
a UNICA trava mantida e o anti-falso-rigor: cada voz traz a lente REAL da sua disciplina sobre
o problema concreto, e CEDE A VEZ se nao tem o que dizer - colegiado VISIVEL, jamais tensao
FABRICADA.

Em relacao ao ADR 0002: reverte parcialmente e por requisito o achado 9 (discriminador
estreito) e o cetico NOVO-2. As demais decisoes do 0002 (disciplina epistemica, pipeline,
anti-falso-rigor, seguranca) seguem intactas.

## Validacao (2026-06-17)

1. Headless de dentro de `debthub-wt`: global carrega + hook dispara (refuta "repos
   sobrepondo / nao propaga").
2. Headless apos a inversao: uma sessao nova, diante de pergunta tecnica, produz a resposta
   COM vozes-especialistas rotuladas (refuta "os especialistas nao aparecem").

## Limite (inalterado)

A ENTREGA do lembrete e deterministica (hook, toda sessao/dir); a ADESAO do modelo continua
soft (piso inerente, ADR 0002 secao 9). O hook eleva fortemente a probabilidade de o colegiado
aparecer, mas nao e garantia absoluta de forma - so o `artifact-discipline.sh` bloqueia de
fato (emoji/lexico em arquivo).

## Corroboracao empirica (2026-06-23, ref: docs/research/referencias-pesquisa-agentes-llm.md)

- Corroboracao INDIRETA: Show and Tell (arXiv:2511.13972) - diretiva + exemplo supera cada um isolado, sustenta a forma ROTULADA do contraditorio. Gap honesto: ate jun/2026 NAO ha estudo que valide 'colegiado visivel' como mecanismo proprio; a decisao apoia-se na reducao de bajulacao (0002) e no contraditorio explicito, nao em metrica propria.
