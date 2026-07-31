# ADR 0012 - Guarda dura do modelo Fable

- Data: 2026-07-31
- Status: aceito

## Contexto e requisito

Requisito do usuario, sem excecao: o modelo Fable NUNCA deve ser usado sem confirmacao
EXPLICITA, e subagente NUNCA pode disparar com Fable.

## Por que isto nao pode ser regra escrita

Instrucao em CLAUDE.md entra como contexto de usuario, com adesao PROBABILISTICA, e a adesao
degrada com densidade de instrucao e com o crescimento do contexto (a falha dominante nessa
degradacao e a OMISSAO). Uma restricao que precisa valer 100% das vezes nao pode depender de o
modelo lembrar dela no turno 80 de uma sessao longa.

Ordem de custo e de garantia dos mecanismos de extensao: **Hooks (custo zero, deterministico)
-> Skills -> Plugins -> MCP**. Uma proibicao dura pertence a primeira camada.

## O buraco que quase ficou aberto

O desenho obvio - "exigir um arquivo de autorizacao" - e teatro se o proprio modelo pode
escrever esse arquivo: ele fabricaria o proprio consentimento. A garantia so existe porque
`artifact-discipline.sh` (PreToolUse em Write/Edit) barra qualquer escrita em
`~/.claude/.fable-allowed`, ANTES da isencao de `.claude/`. O sentinela so pode nascer do shell
do usuario.

## Decisao

`fable-guard.sh`, PreToolUse com matcher `Agent|Task|Bash|Workflow`:

1. **Subagente (`agent_id` presente): negacao INCONDICIONAL.** O sentinela nao e consultado.
2. **Sessao principal:** nega, salvo se o sentinela existir, **pertencer a root**, e conter um
   epoch de expiracao no futuro. O usuario libera com (note o caminho ABSOLUTO - ver o defeito
   abaixo):

   ```
   sudo sh -c 'echo $(( $(date +%s) + 3600 )) > /home/<usuario>/.claude/.fable-allowed'
   ```
3. Fail-CLOSED: sem `jq` ou com input malformado e mencao a Fable, nega. Guarda de politica
   nunca falha liberando.

### Correcao 1 (ADR 0015): o consentimento era FORJAVEL

A versao original dizia que `artifact-discipline.sh` impedia o modelo de criar o sentinela.
Isso cobria apenas Write/Edit. Uma linha de **Bash** escrevia o arquivo e passava - o modelo
fabricava a propria autorizacao e a usava no turno seguinte. Repro do refutador: exit 0.

Duas camadas em resposta. A primeira (bloquear `>`/`tee`/`cp`/`mv`/`touch`/`sed -i`/`ln` sobre
o caminho) e defesa em profundidade e nao fecha o problema: sempre restara uma forma nao
prevista. A segunda fecha: **posse por root**. Um arquivo que o usuario do agente consegue
criar e, por definicao, um arquivo que o AGENTE consegue criar - sao o mesmo usuario. `sudo`
neste ambiente pede senha, que o modelo nao tem. So aqui a "confirmacao explicita" deixa de
ser convencao e vira fato do sistema de arquivos.

### Correcao 2: o comando publicado nao funcionava

O comando original usava `~`. Dentro de `sudo sh -c`, o shell roda como root, `HOME=/root`, e
`~` expande para `/root` - o comando escrevia em `/root/.claude/`, que nao existe. Erro real
relatado pelo usuario: `sh: line 1: /root/.claude/.fable-allowed: No such file or directory`.
Falha C2 (caminho que nao resolve) na instrucao publicada. Use caminho absoluto do HOME real.

### Ataque de symlink, tentado e bloqueado

Ao tentar exercitar o ramo de aceite, apontou-se o sentinela para `/proc/sys/kernel/shmmax` -
arquivo de root cujo conteudo (18446744073692774399) e muito maior que qualquer epoch. Se o
hook usasse `stat -L` ou `readlink -f`, isso autorizaria. Ele usa `stat -c '%U'` sem `-L`, que
reporta o dono do SYMLINK (o usuario), e negou. O comportamento e deliberado e esta comentado
no codigo para nao ser "corrigido" por engano.

A deteccao em Bash e ancorada em POSICAO DE COMANDO (inicio de linha ou apos `;`/`&`/`|`).
Sem a ancora, o hook barrava qualquer comando que apenas contivesse a string - inclusive o
proprio script de teste, um `grep` em documentacao, ou a escrita deste ADR. O defeito foi
encontrado justamente porque o hook bloqueou a primeira tentativa de testa-lo.

## Verificacao executada

### Ramo de ACEITE - verificado com sentinela real (2026-07-31)

Era o unico ramo nunca exercitado, porque exige um sentinela de root que o agente nao
consegue criar - o que e precisamente a garantia. Fechado com o sentinela criado pelo usuario:

```
sentinela: dono root:root, modo -rw-r--r--, 11 bytes, regular file
sessao principal + sentinela de root .......: exit 0  -> AUTORIZA
subagente + o MESMO sentinela valido .......: exit 2  -> NEGA
```

A negacao de subagente sobrevive ao consentimento valido, como o requisito exige.


15 de 15 casos passaram, incluindo: nega na sessao principal sem sentinela; **nega em subagente
mesmo com sentinela valido**; permite na sessao principal com sentinela valido; nega com
sentinela expirado; nega invocacao via CLI; permite `opus`; permite `grep` da palavra em docs;
permite escrever a string num documento; bloqueia `Write` no sentinela com o motivo correto.

## Limite honesto

A deteccao em Bash e defesa em profundidade, nao garantia: uma linha ofuscada (base64, variavel
indireta, `eval`) escapa da ancora. A GARANTIA esta nos dois caminhos deterministicos - o campo
`.model` do Agent (comparacao exata) e o bloqueio incondicional por `agent_id`. Estes cobrem o
requisito literal; o caminho Bash cobre o descuido, nao o adversario.
