# ADR 0018 - Segunda arguicao: o acento que reprovava 25% dos retornos reais

- Data: 2026-07-31
- Status: aceito
- Corrige: 0014 (regex do contrato), 0015 (regra de fixture nao vinculou), 0011 (residuo editorial)
- Veredito recebido: **correcao menor** (revalidacao com o mesmo revisor, sem repipeline)

## O achado grave

`subagent-contract.sh` casava `EVIDENCIA` em ASCII. O `CLAUDE.md` manda os agentes raciocinarem
em PT-BR, e eles emitem `EVIDENCIA` **com acento**. Medido contra os eventos REAIS do log da
sonda, com um unico delta (`sed 's/EVIDENCIA-acentuada/ASCII/'`):

```
FALSO POSITIVO: implementador      (com acento rc=2 / sem acento rc=0)
FALSO POSITIVO: revisor-codigo     (com acento rc=2 / sem acento rc=0)
FALSO POSITIVO: auditor-seguranca  (com acento rc=2 / sem acento rc=0)
FALSO POSITIVO: implementador      (com acento rc=2 / sem acento rc=0)
```

**4 de 16 = 25%**, atribuicao causal 100%, sem confundidor. Um dos retornos bloqueados tinha
36.188 bytes de revisao real com os quatro blocos presentes. O mecanismo criado para punir
afirmacao sem lastro estava acusando de falta de lastro exatamente quem o forneceu - e os
agentes mais caros do pipeline.

Detalhe que fecha o argumento: **o revisor precisou escrever "EVIDENCIA" sem acento no proprio
retorno para nao ser bloqueado pelo defeito que estava reportando.**

## Tres agravantes, e o que eles ensinam

1. **A regex e anterior a correcao da fonte (ADR 0014); esta a tornou load-bearing.** Antes, o
   hook lia o transcript do pai e dava 0 blocos sempre - o acento nunca chegava a importar.
   Corrigir um defeito ATIVOU outro que estava mascarado. Defeito mascarado por defeito nao
   aparece em teste de componente; so aparece quando o primeiro e corrigido.
2. **A suite nao pegava, e nao pegaria.** O fixture era ASCII, escrito a mao, contra a mesma
   suposicao da implementacao. E o teste tautologico que o proprio gate condena: passa porque
   autor e teste compartilham o erro.
3. **A regra do ADR 0015 nao vinculou na primeira aplicacao.** O ADR adotou "hook novo so entra
   com um evento REAL capturado como fixture" e declarou o achado 1 "F2P com payload real". O
   payload usado por acaso nao tinha acento. Havia 209 eventos reais no log da sonda, ali, nao
   usados. **Enunciar a regra nao a executa** - a mesma frase que o CLAUDE.md ja registra sobre
   o C7, agora sobre uma regra criada para impedir exatamente isso.

## Correcao

Nao se acrescentou a variante acentuada de uma palavra - isso repetiria o erro na proxima
(`PROPAGACAO`, `RISCOS`). **Normaliza-se o texto antes de casar**, e todos os padroes passam a
ser ASCII por construcao:

```
NORM="$(printf '%s' "$LAST" | sed 'y/<acentuadas>/<ascii>/')"
```

F2P contra os 18 eventos reais do log: **0 reprovados** (antes: 4 de 16).

## Os demais achados

| Severidade | Achado | Correcao |
|---|---|---|
| MEDIO | A suite fazia `find $HOME/.claude/logs -delete` e destruia o throttle de **todos** os repos do usuario | `limpa_stamp` apaga so o stamp do repo de teste (md5 do ROOT, como o hook calcula); `risk-trigger` roda com HOME isolado. Provado: stamps de outro repo sobrevivem a suite |
| MEDIO | `verify-gate` sem upstream caia em `HEAD~1..HEAD` e acusava trabalho de sessao passada em arvore limpa | Sem upstream, considera so o nao-commitado. Prefere-se falso NEGATIVO ao falso POSITIVO: gate que acusa sem motivo e desligado, e ai nao protege nada. Limite declarado: "commitar nao desliga o gate" vale para repo COM upstream |
| MEDIO | Garantia do Fable dependia de pre-condicao nao publicada (agente != root, sudo com senha) | Publicada no README: em devcontainer/CI como root a garantia e ZERO |
| MENOR | Nota read-only em 4 de 8 agentes read-only - faltava no `revisor-codigo`, o mais invocado | Agora nos 8 |
| MENOR | `implementador\|tdd` no `case` do hook mas fora do matcher: ramo inalcancavel | Deadcode removido |
| MENOR | Teste de regressao por `grep` no texto-fonte passaria se o defeito voltasse com outra sintaxe | Vira teste de COMPORTAMENTO: evento em que o transcript do PAI tem os blocos e o do subagente nao; um hook que lesse o pai aprovaria, o correto reprova |
| EDITORIAL | README publicava 43/43 (medido 55/55) - mesma classe do achado 11, recommitada no paragrafo que anuncia a correcao do achado 11 | Corrigido |
| EDITORIAL | Citacao "Calo e Gurita"; o Crossref traz tres autores | "Calo et al." |
| EDITORIAL | "541 violacoes / 300 UIs" nao verificado na fonte primaria (paywall ACM) | Marcado como nao verificado no ponto de uso |

## Falha de gating, registrada

O diff da correcao criou um caminho de execucao de comando lido do repositorio. Pela regra do
proprio `CLAUDE.md`, isso e superficie que exigia `auditor-seguranca`. **Ele nao rodou.** O furo
foi encontrado depois, pelo autor, e nao pelo gating que deveria te-lo disparado. Segunda
evidencia de que o gating por julgamento da sessao falha exatamente onde mais importa.

## O contrafactual do revisor, adotado

"Se a correcao estivesse errada do jeito mais plausivel, o que pegaria? A suite nao pegaria -
ela testa cada hook contra fixture proprio, e os tres defeitos sao de **interacao**
(hook x payload real, gate x suite, gate x topologia do repo)."

Item que faltava no gate, agora adotado: **nenhum componente e dado por verificado contra
fixture escrito pelo autor quando existe trafego real capturado.** A sonda coleta esse trafego;
ela passa a alimentar a suite.

## Estado

55/55, sem efeito colateral fora do repo sob teste. Condicao explicita do revisor para
revalidacao - fixtures do `subagent-contract` vindos do log da sonda, nao de texto novo escrito
a mao - **cumprida**: a correcao foi validada contra os 18 eventos reais.

Pendente: os ADRs 0016 e 0017 e o `output-budget.sh` chegaram depois do escopo arguido e
**nao passaram por arguicao independente alguma**.
