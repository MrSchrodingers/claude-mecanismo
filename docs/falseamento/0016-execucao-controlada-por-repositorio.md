# ADR 0016 - O gate de conclusao dava execucao de comando a qualquer repositorio clonado

- Data: 2026-07-31
- Status: aceito
- Corrige: 0011 e 0015 (que introduziram e ampliaram `.claude/verify-cmd` sem tratar a superficie)

## O defeito

`verify-gate.sh` lia `$ROOT/.claude/verify-cmd` e executava o conteudo com `sh -c`. Esse
arquivo vem **do repositorio**. Um repo hostil - ou um unico commit hostil num repo legitimo -
obtinha execucao de comando arbitrario na maquina do usuario assim que houvesse qualquer
alteracao de codigo nao-commitada.

Repro executado, com payload inofensivo:

```
repo hostil com .claude/verify-cmd contendo:  printf ... > /tmp/MARCADOR
alterar um arquivo .py, disparar o hook Stop
-> marcador criado. VULNERAVEL.
```

## Por que isto e grave, e nao teorico

E a mesma classe de **CVE-2025-59536** (CVSS 8.7 confirmado na NVD; corrigido em 1.0.111.
A atribuicao a Check Point Research NAO foi confirmada na fonte primaria alcancavel - a
referencia do NVD e o GHSA-4fgq-fpq9-mr3g): configuracao
de projeto controlada por repositorio levando a execucao de comando ao abrir o diretorio. A
Anthropic corrigiu aquele caso gateando a config de projeto atras do dialogo de confianca a
partir da versao 1.0.111.

O agravante: `.claude/verify-cmd` e **invencao desta config**, nao um mecanismo do produto.
Ele nao passa pelo dialogo de confianca. Ou seja, esta config **reintroduziu, por conta
propria, uma superficie que o produto ja havia fechado** - e o fez no hook que mais se orgulha
de "executar em vez de perguntar".

CORRECAO (3a arguicao, achado M6): a versao anterior citava
`skipDangerousModePermissionPrompt: true` como agravante. **Non sequitur, removido.** O
`sh -c "$VCMD"` do hook nao passa pelo sistema de permissao em modo algum - nao havia defesa
residual ali para ser removida. Inflar a severidade com fator irrelevante e o falso-rigor que
a Diretriz 3.1 condena, cometido dentro de um ADR de seguranca.

## Decisao

1. Comando vindo do repositorio so executa se o **hash** do comando estiver em
   `~/.claude/verify-cmd-approved`. Esse arquivo vive FORA de qualquer repositorio, logo um
   clone hostil nao o alcanca.
2. A lista de aprovacao precisa **pertencer a root**. Bloquear as rotas de escrita conhecidas
   e defesa em profundidade, nao garantia - o modelo pode escrever um script e executa-lo, que
   e o modo de falha "Bash opacity" descrito na RFC `anthropics/claude-code#45427` (hooks
   gateiam nome de ferramenta, nao conteudo de comando). Posse por root move a barreira para
   fora do alcance do agente, porque `sudo` pede senha.
3. Sem aprovacao, o hook **nao executa** e cai na auto-deteccao - comando construido por este
   script, nao lido do disco do projeto, portanto nao controlavel por terceiro.
4. `artifact-discipline.sh` e `fable-guard.sh` passam a barrar Write/Edit e as formas de Bash
   sobre `verify-cmd-approved`, pela mesma razao do sentinela do Fable.

Aprovacao pelo usuario, depois de LER o comando:

```
sudo sh -c 'echo "<hash>  # <repo>" >> /home/<usuario>/.claude/verify-cmd-approved'
```

## Verificacao executada

- PoC do repo hostil: **antes** "VULNERAVEL: comando do repositorio FOI EXECUTADO";
  **depois** "SEGURO: comando do repositorio nao foi executado".
- Modelo tentando se auto-aprovar via Write: `exit 2`.
- Lista de aprovacao que nao pertence a root: **ignorada**, com aviso.
- Suite: 55/55, com os tres casos acima como regressao permanente.

## O que este ADR diz sobre o metodo

Todos os defeitos anteriores desta reforma foram de MECANISMO QUE NAO FUNCIONAVA. Este e o
primeiro de MECANISMO QUE FUNCIONAVA DEMAIS: o hook fazia exatamente o que fora projetado
para fazer - executar o comando do projeto - e por isso mesmo era explorável.

Licao: "executa em vez de perguntar" e a tese central desta config, e ela cria superficie. Todo
ponto onde o agente executa algo derivado de dado nao confiavel precisa de um limite de
confianca explicito. A pergunta a fazer em cada hook novo nao e so "isto funciona?", mas
**"de onde vem o dado que isto consome, e quem controla essa fonte?"**
