# ADR 0014 - O contrato de subagente lia o transcript errado

- Data: 2026-07-31
- Status: aceito
- Corrige: 0011 (que classificou este hook como "nao exercitado" quando ele era defeituoso)

## O que aconteceu

O `subagent-contract.sh` da v2 lia `.transcript_path` para achar o retorno do subagente.
MEDIDO no runtime: esse campo aponta para o transcript da **sessao principal**. O hook
inspecionava a ultima prosa do ORQUESTRADOR e emitia veredito sobre ela, acreditando julgar
o subagente.

O defeito e **bidirecional**, e e por isso que era pior que inerte:

- **Falso positivo:** barrou um subagente conforme. O `refutador`, executando contra esta
  propria config, devolveu 4 blocos RESULTADO/EVIDENCIA (`last_assistant_message`, 9.965 B).
  O hook leu o transcript pai, encontrou 0 blocos, e reportou falta.
- **Falso negativo:** aprovaria subagente NAO conforme sempre que a prosa do orquestrador
  contivesse "RESULTADO"/"EVIDENCIA" mais uma ancora - situacao provavel justamente quando o
  orquestrador esta sintetizando o retorno de outros agentes.

O veredito do hook era **descorrelacionado do objeto que ele afirmava verificar**. Inerte nao
mente; este mentia nos dois sentidos.

Efeito colateral que mede a gravidade: o bloqueio indevido **destruiu a entrega do relatorio
do proprio agente que encontrou o defeito**. Os 11 achados restantes tiveram de ser reemitidos.

## Como foi encontrado

Pelo agente `refutador`, com contexto separado, executando contra o diff real da v2. Nao foi
encontrado por leitura de codigo - foi encontrado porque o hook **rodou** e barrou o agente,
e o agente investigou a mensagem de bloqueio que recebeu.

Repro de uma linha, com o extrator do proprio hook aplicado aos dois arquivos:

```
transcript PAI (.transcript_path, o que o hook lia) .....: 0 blocos
agent_transcript_path (568.575 B) .......................: 2 blocos
```

## Duas afirmacoes do ORQUESTRADOR que estavam erradas

Registradas porque o erro de inferencia importa mais que o bug:

1. **"`agent_type` vem vazio no SubagentStop, logo o matcher nunca casa e o hook e inerte."**
   FALSO. Distribuicao real dos 48 eventos capturados: 45 vazios, 1 `general-purpose`,
   2 `refutador`. Os 45 vazios sao **outra classe de evento** (carregam descricao de tool-call,
   nao conclusao de agente). O orquestrador agregou classes distintas, viu ausencia numa
   amostra enviesada e concluiu impossibilidade estrutural. Contou 2 de 48 como zero.

2. **"`last_assistant_message` e linha de status, nao o retorno."** FALSO pelo mesmo erro: os
   34-41 bytes observados vinham dos eventos da outra classe. Nos eventos de agente nomeado,
   o campo tem 9.965 B e 4.616 B - o texto final completo.

Licao: **ausencia numa amostra nao e impossibilidade.** Antes de concluir "o mecanismo nao
pode funcionar", separe as classes de evento e confirme que a classe que importa esta na
amostra. Foi o mesmo erro do `verify-gate` sob outra forma - concluir do artefato em vez de
concluir da execucao.

## Decisao

Fonte do retorno, em ordem de preferencia (todas medidas no payload real):

1. `.last_assistant_message` - texto final completo do subagente, entregue pelo runtime.
   Dispensa parsing de transcript.
2. `.agent_transcript_path` - transcript do subagente. Existe durante a execucao e pode sumir
   depois; por isso e fallback, nao fonte primaria.
3. `.transcript_path` - **NUNCA**. E o pai. Usa-lo foi o defeito.

Alem disso, a filtragem por tipo de agente passa a ser feita DENTRO do hook, e nao apenas pelo
matcher do `settings.json`: com 45 de 48 eventos trazendo `agent_type` vazio, filtrar aqui
garante que o hook so opine sobre o que sabe julgar, e cale no resto.

## Verificacao executada

11 de 11, usando o **payload real capturado pela sonda**, nao fixture escrita a mao:

- REGRESSAO (F2P): o evento exato que o hook antigo barrou por engano agora passa (exit 0).
- O falso positivo foi reproduzido e eliminado: fonte antiga 0 blocos, fonte nova 2 blocos.
- Falso negativo: retorno sem evidencia e barrado (exit 2), com o motivo correto.
- `EVIDENCIA` sem ancora (`arquivo:linha`, comando ou exit code) e barrada.
- Silencioso em `agent_type` vazio e em `general-purpose`, com stderr limpo.
- `stop_hook_active` respeitado.

## O que este ADR diz sobre o metodo, e nao sobre o bug

Este e o **terceiro** mecanismo da v2 publicado como garantia e depois encontrado quebrado
(apos `verify-gate.sh` e as referencias mortas). Os tres tem a mesma causa: o orquestrador
verificou o ARTEFATO (sintaxe, `bash -n`, fixture proprio) e chamou de verificado, quando o
que falhava era a INTEGRACAO com eventos reais do runtime.

Consequencia adotada: **hook novo so entra com um evento REAL capturado como fixture.** Sonda
em `SubagentStart`/`SubagentStop` (`hooks/subagent-probe.sh`) fica como componente permanente
de instrumentacao, e nao como ferramenta descartavel - foi ela que tornou este defeito visivel.

Corolario mais amplo, e o unico argumento de eficacia da arquitetura v2 que tem evidencia
direta: **o defeito foi achado por um agente de contexto separado, que corrigiu o orquestrador
em dois pontos.** Nao foi achado por revisao na mesma resposta. E a descorrelacao funcionando
sobre o proprio sistema que a implementa.
