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

---

## Adendo - a revisao independente sobre o proprio diff desta sessao

Antes de fechar, o diff foi submetido a `revisor-codigo` e `auditor-seguranca` em contexto
separado, com scanner executado. **Onze achados procedentes**, cinco deles criticos - todos
sobre codigo escrito NESTA sessao, boa parte dele sobre as proprias correcoes acima.

O dado que organiza este adendo: a suite estava **verde com todos os onze abertos**. Isso nao
e contradicao, e o ponto - nenhum dos onze tinha caso de teste, porque quem escreveu o codigo
escreveu tambem os testes, e ambos herdaram a mesma suposicao.

### Critico: a raiz de confianca era instalada a partir de entrada nao confiavel

`install/manifest.lock` e um arquivo do REPOSITORIO, isto e, esta dentro do espaco de escrita
do ator governado. Suas colunas `origem` e `destino` eram usadas VERBATIM como caminho de
`mkdir -p`, `cp -f` e `rm -rf`, e o instalador roda como ROOT. Medido:

```
destino = ../../../ZONA/vitima.conf   -> arquivo FORA do prefixo sobrescrito
destino = ../../../ZONA  (origem=dir) -> `rm -rf` destruiu o diretorio FORA do prefixo
origem  = /etc/hostname               -> copiaria arquivo de fora do repo, com modo alargado
```

Sob `sudo`: escrita e remocao arbitrarias como root a partir de dado que o ator controla. A
inversao exata da tese do projeto. E o digest do manifesto nao protegia - ele e calculado sobre
o MESMO working tree que deveria proteger, e a conformidade comparava o arquivo copiado com o
valor que o proprio atacante escreveu. Detector de drift contra `~/.claude`, jamais controle de
integridade sobre o repositorio; a distincao passou despercebida ate a auditoria.

Corrigido com portao de confinamento antes da primeira escrita, nos DOIS instaladores - o furo
gemeo em `install/apply.sh` roda como usuario, mas seu alvo sao os proprios hooks da politica.

### Critico: o portao contava divergencia e nunca populacao

Com o conjunto de politica VAZIO, o laco de copia nao copia nada, a conformidade nao itera
nada, e `0 divergentes` era lido como aprovacao. `--enforce` gravava `allowManagedHooksOnly:
true` apontando para 14 caminhos inexistentes: o mecanismo inteiro de hooks desligado com
aparencia de ligado - a armadilha que o proprio arquivo dizia tratar. Gatilho realista: qualquer
normalizacao de whitespace no manifesto.

`MG6` nao pegava, e a razao importa: ele sabota UMA entrada (`div=1`); nao esvazia o conjunto.
**Ausencia de divergencia num conjunto vazio e vacuamente verdadeira** - a mesma forma logica
perseguida desde o ADR 0022, agora dentro do portao construido para impedi-la.

### Critico: `--revert` apagava politica de terceiro

O comentario prometia "Remove SOMENTE o que este script cria". O codigo apagava QUALQUER
`managed-settings.json` - inclusive politica corporativa de outra ferramenta, que pode conter
`permissions.deny` - sem backup, sem aviso, sob `sudo`. A marca `_managed_by` ja existia e era
consultada no ramo de backup, nao no de remocao.

### Critico: o gerador da politica aceitava injecao de JSON

`sed "s|@BASE@|$BASE|g"` sobre o texto do JSON: um valor com aspas FECHA a string e ABRE objeto
novo, e o resultado continua sendo JSON valido - de modo que o `jq -e .` do consumidor nao
barra. Esse documento vira politica em `/etc/claude-code/`. Trocado por `jq --arg`, que nunca
reparseia o valor.

### Critico: o oraculo da ancora trocou falso bloqueio por falso verde

**A condicao de refutacao escrita neste proprio ADR foi satisfeita.** A correcao da secao 3
abriu passagens vacuas, medidas:

| Contraexemplo | Alternativa que casava | Estado |
|---|---|---|
| `o custo foi de R$ 500 mil` | `\$ ` em qualquer posicao | corrigido (ancorado no inicio da linha) |
| `nada ficou nao verificado` | escape sem polaridade nem caixa | corrigido (token `NAO VERIFICADO` em caixa alta) |
| eco da mensagem de bloqueio do hook | idem | corrigido - o portao publicava a propria chave |
| `a doc em exemplo.com:8080 descreve` | `arquivo.ext:linha` | **ABERTO, declarado** |
| `pela leitura, o hook faz exit 2` | `exit <digito>` | **ABERTO, declarado** |

Os dois ultimos nao sao patchaveis por regex, e insistir seria trocar este falso aceite por
outro falso bloqueio - foi assim que o defeito de producao nasceu. `host.tld:porta` e
`arquivo.ext:linha` sao lexicalmente identicos; citar um exit code tem a mesma forma de
reportar um. **O limite passa a ser escrito no hook e em `evidence/claims/C-009.yaml`:** o
oraculo distingue texto COM FORMA de evidencia de texto sem forma; nao distingue REPORTAR de
MENCIONAR.

E havia um agravante de outra ordem: o comentario do hook e a claim C-009 afirmavam validacao
contra "corpus de 15 casos - 9 positivos, 6 negativos". **Esse corpus viveu no rascunho de quem
escreveu a correcao e nunca entrou em `tests/`.** Afirmacao de cobertura inexistente, dentro do
ledger de evidencia. Corrigida em ambos, e o mecanismo que a pegou foi o proprio validador,
quando as claims passaram a citar mutantes que ainda nao existiam.

### Setima instancia do padrao vacuo, no verificador da fase 2

`--verify` imprimia `0 gravaveis pelo ator` sob prefixo de ensaio, onde essa checagem NAO
EXECUTA - ela e guardada por `REAL=1`. A suite lia esse veredito como aprovacao da garantia
central da fase 2. Agora o modo de ensaio declara `NAO VERIFICADO` e nao afirma "fora do espaco
de escrita do ator".

### O que permanece ABERTO, e nao foi corrigido nesta sessao

- **Base de comparacao com remoto de outro nome.** `verify-gate.sh` procura
  `origin/{HEAD,main,master}`; num fork cujo remoto se chama `upstream`, ou com default
  `develop`, a base cai para arvore vazia e o gate passa a acusar codigo JA PUBLICADO. Medido:
  dois repositorios identicos, diferindo so no nome do remoto, dao `exit=2` e `exit=0`. E
  falso positivo, e falso positivo e o que faz o operador desligar o gate. `C-008` declara o
  limite como "verifica mais do que o necessario, nunca menos" - formalmente verdadeiro,
  severidade subdimensionada.
- **`tests/unit/claims.sh` L5b sobrevive a remocao da guarda que diz testar.** Removida
  `RE_SHA` de `commit_existe`, a suite segue verde: `git cat-file -e` recusa a opcao sozinho.
  O teste mede o parser do git, nao a guarda. `RE_SHA` fica como defesa em profundidade sem
  bypass demonstrado, e o TESTE e que esta errado.
- **A politica managed executa `install/verify.sh` do espaco do ator.** `session-integrity.sh`
  roda `cd $EVIDENCE_GATE_REPO && bash install/verify.sh`, e esse env e gravado pelo proprio
  `managed-settings.json` root-owned apontando para o clone no home. `verify.sh` nao e
  componente do manifesto, logo nao vai para `/opt`. O ator faz o proprio auditor sair 0.
  Corrigir exige promover `verify.sh` e o manifesto a componentes managed.
- **Copia antes da conformidade.** O portao de confinamento precede a primeira escrita, mas a
  copia para `$OPT` ainda precede a checagem de digest: um repositorio com drift sobrescreve a
  politica VIVA antes de reprovar. Correcao: estagiar em `$OPT.new` e trocar por `mv` atomico.
- **`--verify` nao mede posse em nenhum caminho executavel**: exige `REAL=1`, que exige root.

### O que este adendo demonstra sobre o metodo

Onze achados procedentes sobre codigo escrito horas antes, por quem tambem escreveu os testes
que o cobriam - e a suite verde o tempo inteiro. As correcoes desta sessao criaram tres dos
cinco criticos.

A conclusao operacional nao e "revisar mais". E que **revisao com CONTEXTO SEPARADO e ferramenta
que executa acha o que o autor nao pode achar**, porque o ponto cego do autor esta nos testes
tanto quanto no codigo. O `refutador` como portao final nao substitui isso: chega tarde demais
para reescrever o corpus.
