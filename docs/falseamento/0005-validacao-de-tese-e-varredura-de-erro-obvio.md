# ADR 0005 - Validacao de tese, orquestrador-conciliador e varredura de erro obvio

- Data: 2026-06-17
- Status: Aceito (validacao adversarial + dinamica em andamento)
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0002 (disciplina epistemica, pipeline), 0004 (colegiado visivel)

## Contexto

Dor central, declarada pelo usuario: ERROS OBVIOS e superficiais passaram por revisao e
causaram problemas. O pedido: um colegiado de especialistas com um PROFESSOR-DOUTOR
ORQUESTRADOR-CONCILIADOR, e o rigor academico de validacao de uma TESE aplicado a planos,
PRDs, ideias, features e fixes - garantindo qualidade, revisao, robustez, criticidade e
nao-bajulacao.

Fundamentado em pesquisa de 3 frentes paralelas, com filtro de fonte rigoroso (peer-reviewed
e institucional acima de blog/relato; anedota rotulada; numeros contestados nao promovidos a
fato). Inspiracao de forma: os arquivos skill-builder/agent-builder do usuario (instrucao
binaria e testavel, roteamento SE->FAZER, porque causal, entrega+verificacao).

## Decisao

1. **Orquestrador-Conciliador (presidente da banca).** Voz/papel que CONDUZ o colegiado e
   GARANTE O PROCESSO - nao e mais um juiz do conteudo: assegura que nenhuma objecao material
   ficou sem replica com evidencia, adjudica divergencia pela evidencia (nao eloquencia),
   intervem se a arguicao for frouxa, NUNCA substitui os arguidores (I.2.4.5). Persona em
   I.2.2; papel na Diretriz 13.1.

2. **Validacao de tese - tres portoes logicos (Diretriz 13.1):** G1 premissas explicitas e
   operacionais (separar factual de requisito; pressuposicao oculta = alerta); G2 inferencia
   valida (cacar afirmacao do consequente; abducao gera, deducao fecha); G3 solidez (valido
   != solido; premissa factual nao medida = hipotese a verificar, nunca "aprovado").

3. **Varredura de erro obvio (gate DO-CONFIRM binario C1-C10):** rodado sobre a evidencia
   BRUTA antes do veredito; qualquer FALHA bloqueia (stop-the-line/jidoka), nunca nota de
   rodape. C3/C7/C9 atacam diretamente a dor (sucesso nao testado, citacao nao verificada,
   sinal tolerado).

4. **Desfecho CALIBRADO (nao binario):** aprovar(raro) / editorial / menor(sem repipeline) /
   revisar-e-ressubmeter(repipeline inteiro) / rebaixar escopo / reprovar. O binario
   aprova/reprova e o que empurra para o "passa" e deixa o obvio escorregar.

5. **Skill `/defesa-de-tese`** (invocacao explicita) + reforco do `revisor-critico` (gate
   C1-C10 + veredito calibrado + meta-review) + reforco do hook UserPromptSubmit (orquestrador
   + varredura antes de "pronto").

## Base de evidencia (3 frentes, confianca anotada)

Frente A - validacao academica e metodo cientifico:
- Presidente de banca/chair GARANTE PROCESSO, nao avalia conteudo: UCL (independent chairs),
  St Mary's (4 deveres), convergencia de 5+ regulacoes institucionais [confianca alta].
- Handling editor/area chair ADJUDICA divergencia e escreve meta-review: Wiley, ACM [alta].
- Desfecho calibrado (escala de 5-6, nao binario): Univ. Leeds (categorias verbatim) [alta].
- Metodo como fluxo: Popper (falseabilidade, 1959), Lakatos (progressivo vs degenerativo,
  1970), Kuhn (anomalia/crise, 1962) - todos ja na biblioteca I.2.5 [alta].

Frente B - captura de erro obvio e qualidade-fluxo:
- Checklist DO-CONFIRM: Gawande, *The Checklist Manifesto* (2009), origem Boeing 299 [alta].
  WHO Surgical Safety Checklist: Haynes et al. NEJM 2009 (direcao) MAS Urbach et al. NEJM 2014
  (replicacao NULA em 101 hospitais) -> direcao alta, MAGNITUDE BAIXA, nao importar numero.
- Normalization of deviance: Vaughan, *Challenger Launch Decision* (1996) [alta] - fundamenta
  a Diretriz 2.1 (sinal tolerado, C9).
- Swiss cheese / latente vs ativa: Reason, *Human Error* (1990) [alta] - fundamenta os DOIS
  LEITORES; condicao latente so se fecha virando barreira ativa (hook), nao disciplina.
- Premortem: Klein (HBR 2007) [tecnica: alta]; o "30%" e de Mitchell/Russo/Pennington (1989),
  estudo unico, outro dominio [numero: media-baixa, NAO importado].
- Red team / SAT / devil's advocacy: Heuer (tradecraft CIA) [alta]; groupthink: Janis [alta].
- Qualidade como fluxo: jidoka/andon (Toyota), poka-yoke (Shingo, *Zero Quality Control*),
  Deming (*Out of the Crisis*, 1982, ponto 3 "cease dependence on inspection") [alta].
  Shift-left: direcao media-alta; multiplicadores "1x->100x" proveniencia fraca, contestados
  por Menzies et al. (2016) [BAIXA, NAO importado].

Frente C - logica formal e filosofia da linguagem:
- Validade vs solidez; consequencia logica; deducao/inducao/abducao: SEP/IEP [alta].
- Afirmacao do consequente / negacao do antecedente (falacias formais) [alta].
- Correcoes de atribuicao confirmadas: Teoria das Descricoes e de Russell (1905), NAO Frege;
  completude de Godel (1929/30) != incompletude (1931); Tarski (1933/35), Frege Sinn/Bedeutung
  (1892) [alta].
- Risco declarado: a maioria do raciocinio de engenharia e ABDUTIVA - nao exigir prova
  dedutiva de toda hipotese (seria o espelho do falso rigor); Godel e "o teorema mais abusado"
  - nao invocar como metafora de incerteza.

## Trade-offs e limites honestos

- **Transferencia de dominio nao e medida.** A evidencia forte e de dominios fisicos
  (cirurgia, aviacao, NASA, manufatura). A eficacia em revisao por agente de IA e analogia
  plausivel, NAO resultado medido. O usuario deveria MEDIR a taxa de erro obvio antes/depois
  do gate (coerente com a secao 13: contencao e hipotese a medir).
- **Numeros contestados deliberadamente nao promovidos a fato** (WHO magnitude, 100x custo,
  30% premortem) - importar qualquer um seria o falso rigor que a Diretriz 3.1 proibe.
- **Limite estrutural (Reason/Shingo):** o gate so funciona se for INVOCADO; checklist que
  depende de memoria herda a falha que corrige. Defesa robusta = mover C2/C3/C8 para
  HOOK/poka-yoke (pendencia futura); o restante e disciplina, nao garantia.
- **Custo:** so o desfecho "revisar-e-ressubmeter" paga o repipeline completo - preserva o
  gating da secao 13; o resto corrige sem segunda banca.
- **Entrega deterministica (hook), adesao soft** - mesmo piso inerente do ADR 0002 secao 9.

## Validacao (executada 2026-06-17)

1. Prova dinamica (headless): uma sessao nova, dentro de um projeto, recebeu um IDOR disfarcado
   de "simplificacao" + um "testei e funciona" nao testado, e REPROVOU - convocou o
   [Orquestrador] + [Auditor]/[Logico-Epistemologo], pegou o IDOR (A01) e a afirmacao do
   consequente (C3), rodou a varredura (C1/C3/C6/C10 = FALHA) e emitiu veredito calibrado. O
   erro obvio que antes passava nao passou.

2. Defesa adversarial do PROPRIO design (cetico, eat-your-own-dog-food). Achados incorporados:
   - F-D: removido o prior nao medido "aprovar limpo deve ser RARO" (era ele proprio um C7 -
     numero sem fonte - e induzia a discordancia gratuita que a Diretriz 3 proibe). Substituido
     por: aprovar limpo e legitimo sem furo real; reprovar/repipeline sem furo e o defeito
     simetrico a bajulacao.
   - F-A/F-B (anti-conluio): o orquestrador e a sessao-autora; para tese NAO trivial (inclusive
     plano/PRD/ideia, onde nao ha git diff) a arguicao adversarial e DELEGADA a um arguidor
     independente (cetico/revisor-critico). "Evidencia bruta" generalizada de "git diff" para
     "os artefatos reais que a tese referencia, lidos direto, nao a prosa do autor".
   - F-C: aplicabilidade por relevancia - item inaplicavel (ex.: C3/C6 sobre plano nao
     implementado) marca-se N/A COM justificativa de uma linha (auditavel); para plano, C3/C6
     leem-se como "a tese nomeia o teste falseavel e o risco de regressao a checar".

Poka-yoke C2/C8 (PARCIALMENTE FECHADO - 2026-06-17): hook PostToolUse `poka-yoke-lint.sh`
linta o arquivo de CODIGO recem-escrito/editado e devolve o achado ao modelo via exit 2
(jidoka/stop-the-line), tirando C8(deadcode) e C2(sintaxe/simbolo) da memoria e os tornando
barreira ativa (Shingo). Cobertura medida: Python via ruff (F401 import nao usado, F821
indefinido, F841 var nao usada, E9 sintaxe; carve-out de F401 em __init__.py por re-export
legitimo); fallback pyflakes/py_compile; sintaxe JS via node --check. FAIL-OPEN: sem linter
para o tipo, nao bloqueia (lint e auxiliar, nao guarda de seguranca como o artifact-discipline).
Validado em 8 casos (pega F401/sintaxe py+js, passa limpo, isenta __init__/nao-codigo, fail-open).

LIMITE honesto do NAO mecanizado: (a) C2 sobre paths citados na PROSA do chat (nao em codigo)
segue disciplina - parsear NL por regex daria falso positivo (falso rigor, 3.1); (b) TS/TSX nao
tem checagem standalone confiavel sem o tsc do projeto; (c) a transferencia de dominio
(cirurgia/aviacao -> agente de IA) segue analogia NAO medida - o ganho real exige medir a taxa
de erro obvio antes/depois. Os demais C-itens (C1/C4/C5/C6/C7/C9/C10) nao sao regex-aveis e
permanecem disciplina + gate do revisor-critico.

## Corroboracao empirica (2026-06-23, ref: docs/research/referencias-pesquisa-agentes-llm.md)

- Qualidade do plano domina o resultado: Plan-Then-Execute (CHI 2025, peer-reviewed: plano ruim 1.8% vs bom 66.7%).
- Auto-critica SEM sinal externo degrada: arXiv:2310.08118 - sustenta a regra C3 'sem teste executado, nao declaro correto' e o ancoramento em execucao.
- Erros em arvores de decomposicao profundas concentram-se na AGREGACAO (68%): ARIES (arXiv:2502.21208) - sustenta o portao final unico (revisor-critico) em vez de profundidade.
