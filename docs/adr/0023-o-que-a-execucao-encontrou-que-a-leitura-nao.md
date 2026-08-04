# ADR 0023 - O que a execucao encontrou, e a leitura nao

- Data: 2026-08-04
- Status: aceito
- Sessao: fechamento da Fase 1 (M2 -> M3), a partir de `docs/HANDOFF.md`
- Complementa: 0022 (fecha a condicao de refutacao declarada la)

## O achado que organiza este ADR

O handoff previa cinco itens de P0/P1/P2 e nenhum defeito. A sessao fechou os itens e encontrou
**oito defeitos**, todos por EXECUCAO. Nenhum por leitura de codigo, nenhum por revisao.

| # | Defeito | Como apareceu |
|---|---|---|
| 1 | ancora de evidencia reprovava retorno real bem ancorado | rodar um subagente de verdade e ler o payload da sonda |
| 2 | `nao verificado` era inexequivel - o hook bloqueava o que ele mesmo instrui | testar a instrucao publicada |
| 3 | R4 era vacua: campos que o hook nao le | mutacao sobre a garantia que R4 dizia proteger |
| 4 | comentario obsoleto contradizendo codigo e matcher | conferir o matcher real |
| 5 | gate inerte em branch sem upstream | montar o cenario e rodar |
| 6 | suites nao reentrantes corrompem-se com FAIL plausivel | rodar duas ao mesmo tempo |
| 7 | S2 nao via pacote sem aspas simples; S1 quebrava com espaco duplo | gerar variantes de formatacao |
| 8 | `--enforce` gravava a politica antes de conferir; `--revert` nao revertia | exercitar o proprio instalador |

Os defeitos 1, 2, 7 e 8 sao de SEGURANCA ou de disponibilidade do mecanismo. Os defeitos 3 e 6
sao do aparato de teste - isto e, do que deveria detectar os demais.

## 1. A condicao de refutacao do ADR 0022 foi testada, e nao se realizou

O ADR 0022 declarava: "Se `~/.claude` nao fosse o escopo efetivo - por exemplo, se plugins
instalados sobrescrevessem os hooks em tempo de execucao". Enquanto nao observado, a tese
central tinha premissa aberta.

O handoff afirmava que so o usuario poderia observar, via `/hooks`. **Parcialmente falso.**
`/hooks` e `/status` sao da TUI; `--debug` e flag de CLI; e existe observavel mais forte que
qualquer um dos dois: `--include-hook-events` com `--output-format=stream-json` emite
`hook_started` e `hook_response` com `exit_code` e `outcome`. `/hooks` mostra o CONFIGURADO;
isto mostra o EXECUTADO.

Predicao registrada antes do tratamento e confirmada exatamente (2->3, 4->5, 3->4 por evento,
com o heartbeat do hook de usuario continuando a incrementar): **hooks de plugin SOMAM aos de
escopo de usuario.** O total por evento e a uniao dos escopos, filtrada por `matcher`.

A tese do 0022 permanece, agora com premissa medida.
Registro completo: `evidence/observations/2026-08-04-precedencia-de-hooks.md`.

## 2. A fronteira externa passou a impor - e isso foi medido, nao configurado

Ruleset ativo com `bypass_actors: []`. O que importa nao e te-lo criado:

```
$ git push origin fase1/contrato-ancora:main
remote: error: GH013: Repository rule violations found for refs/heads/main.
 ! [remote rejected]   exit=1   origin/main inalterado em 92908d1
```

O push partiu do token com `admin: true` - o ator governado na sua maior autoridade - e foi
recusado. `¬bypass(ator, politica)` deixa de ser aspiracao.

Limite que permanece, e que o README precisa dizer: quem tem admin pode DESATIVAR o ruleset. O
provado e que nao ha bypass DENTRO da regra. Desativar deixa rastro no audit log; contornar em
silencio nao deixaria. E a diferenca entre as duas coisas e todo o alcance possivel sem uma
autoridade organizacional acima do dono do repositorio.

## 3. O defeito mais consequente: o mecanismo pressionava na direcao de fabricar evidencia

`subagent-contract.sh` bloqueia retorno sem ancora de evidencia. Medido sobre payload REAL:

```
- Comando: `wc -l .../verify.sh` -> saida `71 .../verify.sh`, exit code `0`.
   -> BLOQUEADO: "Faltou: ANCORA-DE-EVIDENCIA"
```

Duas causas, ambas da mesma classe - o oraculo reconhecia evidencia por CONVENCAO LEXICAL e nao
por estrutura:

- `0x60` (crase de markdown) entre `code ` e `0` derrotava o padrao. Escrever ``exit code `0` ``
  e a forma normal de um agente formatar.
- a lista de comandos era FECHADA. `wc`, `xxd`, `stat`, `make` ficavam de fora. Enumerar
  comandos nao e conjunto decidivel: a allowlist so cresce por remendo.

E havia o terceiro, pior que os dois: a mensagem de bloqueio promete por escrito que
`nao verificado` e resposta valida, e o CLAUDE.md secao 4 tambem. **Medido: um retorno
declarando nao-verificacao recebia exit 2 identico ao de prosa vazia.**

A consequencia e estrutural, nao cosmetica. O unico caminho estavel para atravessar o portao
era APRESENTAR uma ancora. Um mecanismo criado para punir alegacao sem lastro estava
selecionando, entre os agentes, aqueles que produzem a APARENCIA de lastro. Isso e pior do que
nao ter o mecanismo: sem ele, "nao verifiquei" e apenas nao dito; com ele, e penalizado.

## 4. O aparato de teste tinha os mesmos defeitos que deveria detectar

**R4 era vacua.** Montava o payload com `transcript_path` e `subagent_type`; o hook le
`agent_type` e `last_assistant_message`. Com `agent_type` vazio, o hook saia no filtro de tipo
e nunca chegava a normalizacao que R4 dizia proteger. Provado por mutacao: removida TODA a
normalizacao, R4 antiga seguia verde nos dois locales; com os campos corretos, o mesmo mutante
morre. **Sexta instancia do padrao** `precondicao falha -> operacao nao executa -> pos-condicao
vacuamente verdadeira -> verde`.

**A ancora so tinha casos positivos.** O caso "barra retorno sem evidencia" reprovava ja no
`RESULTADO`, entao o poder discriminante da ancora nunca fora exercitado. Positivo sem negativo
correspondente mede PRESENCA, nao poder de decisao. Corrigido, e o mutante MC4 (oraculo que
aceita tudo) so pode ser morto por esse caso negativo.

**O contrato de subagente nunca fora validado por mutacao** - justamente o hook com o pior
historico do projeto (ADRs 0014, 0018, adendo 6 do 0022). `tests/mutation/contrato.sh`, 5
mutantes, cada um morto no caso-alvo.

## 5. Testes de propriedade acharam dois detectores de seguranca furados

`tests/unit/propriedades.sh` afirma propriedades sobre FAMILIAS de entrada. Na primeira
execucao:

- **S2 so enxergava tokens iniciados por aspa simples.** `pip install requests` e
  `pip install "requests"` PASSAVAM. Um pacote sem pinagem atravessava o gate inteiro por
  diferenca de formatacao - a propria classe que S2 existe para impedir.
- **S1 recortava por `${line#*uses: }`**, com um espaco literal. `uses:  a/b@v1` produzia
  string vazia e a action nao pinada passava batida.

Nenhum dos dois seria encontrado por mais um caso por exemplo escrito por quem escreveu o
detector: o exemplo herdaria a mesma suposicao de formatacao. Esta e a justificativa completa
para o metodo, e ela e especifica - nao vale "propriedades sao melhores".

## 6. Concorrencia: a corrida produzia vermelho PLAUSIVEL

Reproduzido: `tests/mutation/contrato.sh` (que muta o hook no lugar) concorrente com
`tests/unit/run.sh` fez este ultimo reportar `FAIL BARRA blocos completos SEM ancora
(got=0 want=2)`, exit 1. Isolada no instante seguinte: 45/45.

O perigo nao e a vermelhidao - e ela ser plausivel. O caso acusado parece defeito real, e o
operador depuraria algo que nao existe. A corrida simetrica tambem cabe: suite lendo o hook
MUTADO (mais permissivo) durante a janela mascara defeito real.

`tests/lib/lock.sh` FALHA RAPIDO em vez de serializar. Esperar faria as duas passarem, que e a
absorcao silenciosa que este repositorio existe para nao fazer. O lock mora em `.git/`, nao em
`$TMPDIR`: exclusao mutua ancorada em variavel de ambiente nao e exclusao mutua.

## 7. Claim ledger: o que o torna util nao e o formato

`evidence/claims/*.yaml`, 16 alegacoes. A regra que o distingue de prosa formatada: **toda
referencia a evidencia e resolvida contra a suite real, e citar regressao ou mutante inexistente
REPROVA.** O inventario (32 regressoes, 16 mutantes) e DERIVADO de `tests/` a cada execucao -
lista digitada seria segunda copia da verdade.

Ha autochecagem: extracao vazia sai 2 (NAO VERIFICADO), nunca 0. Sem ela, uma regex quebrada
reprovaria tudo (falso vermelho) ou, frouxa demais, aprovaria tudo (falso verde).

Dos 15 casos de `tests/unit/claims.sh`, 12 sao negativos. E um deles nasceu passando pelo motivo
errado - o fixture era YAML invalido e a reprovacao vinha do parser, nao da resolucao.

## 8. Raiz de confianca: duas correcoes ao plano do handoff

O handoff previa "migrar os 14 hooks para plugin force-enabled ANTES de ativar". Conferido na
fonte primaria:

> `allowManagedHooksOnly` | (Managed settings only) Only managed hooks, SDK hooks, and hooks
> from plugins force-enabled in managed settings `enabledPlugins` are loaded. User, project,
> and all other plugin hooks are blocked.

Correcao 1: o escape e `enabledPlugins` DENTRO do managed settings. E como conteudo de plugin
mora em `~/.claude/plugins`, gravavel pelo ator, plugin nao serve de raiz: politica root
apontando para script user-owned e raiz de confianca so no nome.

Correcao 2: **nao bastam os hooks.** `verify-gate.sh` le a tabela em `$CLAUDE_ADAPTERS_DIR`;
`doctool.sh` le `$DOC_ADAPTERS_DIR`; `read-budget.sh` executa os doctools. Com a tabela
gravavel, o ator desliga o gate sem tocar em hook nenhum. O deploy managed cobre 30 componentes.
Agentes e skills seguem em `~/.claude` por decisao declarada: sao capacidade, nao politica.

E o instalador tinha dois defeitos proprios, achados antes de qualquer entrega: `--enforce`
gravava a politica ANTES de conferir o deploy (deploy incompleto derrubaria o mecanismo
inteiro - a armadilha exata do handoff), e `--revert` nao revertia (restaurava um "backup" que
o proprio instalador havia criado).

## O que NAO foi feito, e por que

- **`allowManagedHooksOnly` nao foi ativado.** Exige `sudo`, que exige senha nesta maquina. O
  instalador foi exercitado integralmente contra prefixo de ensaio (23 assercoes), mas a
  afirmacao "o runtime honra a flag" so pode vir de medicao com root. Ate la o estado e
  NAO VERIFICADO, e o `status.generated.md` continua dizendo `governed=user`.
- **Sem corpus de eficacia (P4).** Nenhuma afirmacao sobre melhoria de engenharia e dizivel.
- **Sem auditoria autoralmente independente (P5).** A CI executa testes escritos pelo mesmo
  processo, contra os mesmos oraculos. Continua sendo observador ambiental.
- **Sem sandbox.** `pandoc`, `libreoffice` e `pdftotext` seguem processando entrada nao
  confiavel com a autoridade do usuario. Esta e a lacuna aberta mais relevante, e ela DEVE
  travar a expansao para OCR e novos formatos ate haver isolamento.
- **`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` continua nao verificado.**

## O que refutaria este ADR

- Se, sob outra versao do runtime ou outra plataforma, hooks de plugin SOBRESCREVESSEM os de
  usuario, a secao 1 cai e com ela a premissa do 0022. A medicao e de uma versao e uma
  plataforma.
- Se `allowManagedHooksOnly`, ativado, NAO bloqueasse hooks de usuario, a secao 8 estaria
  descrevendo uma garantia que nao existe. Nao foi medido.
- Se o oraculo da ancora, corrigido, passasse a aceitar retorno sem lastro em uso real, a
  correcao da secao 3 teria trocado falso bloqueio por falso verde. O corpus tem 15 casos e 6
  negativos; nao ha medicao em producao.

## O padrao, com oito instancias novas

O ADR 0022 fechava dizendo que o avanco nao veio de parar de errar, mas de tornar erros
observaveis. Esta sessao acrescenta uma distincao mais estreita: **os oito defeitos foram
encontrados por MUDAR O QUE EXECUTA, nao por olhar mais.**

Rodar o binario de verdade; rodar sob outro locale; rodar duas vezes ao mesmo tempo; rodar com
um plugin a mais; gerar variantes de formatacao; mutar a garantia. Leitura atenta do mesmo
codigo, pela mesma pessoa que o escreveu, encontrou zero deles - inclusive nas passagens onde a
regra violada estava escrita no comentario logo acima.
