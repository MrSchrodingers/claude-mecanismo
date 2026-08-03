# ADR 0021 - Contrato de canal: o que o runtime entrega ao modelo

- Data: 2026-07-31
- Status: aceito
- Corrige: 0011 (risk-trigger), 0019 (self-mod-audit e a alegacao de 100% de sobreposicao)
- Veredito da 4a arguicao: **revisar-e-ressubmeter**

Este ADR existe porque a 4a arguicao nao encontrou um bug: encontrou um **erro de camada**, e a
resposta certa a erro de camada e um contrato, nao um patch.

## O defeito

Hook nao "escreve para o modelo". Ele escreve num de varios canais, e **so alguns chegam**.
Medido por A/B com controle positivo (o hook comprovadamente rodou, gravando um marcador em
disco), mais confirmacao no trafego real desta sessao:

| Canal | Attachment gerado | Chega ao modelo? |
|---|---|---|
| `exit 2` (stderr vira `blockingError`) | `hook_blocking_error` | **SIM** |
| `hookSpecificOutput.additionalContext` | `hook_additional_context` | **SIM** |
| `stdout` de `UserPromptSubmit` | `hook_success.content` | **SIM** |
| **`stderr` com `exit 0`** | `hook_success` com `content` **VAZIO** | **NAO** |

Confirmacao no proprio transcript: `hook_success` com `stderr=368 B` e `content=''`.

Consequencia: `risk-trigger.sh` e `self-mod-audit.sh` eram **decoracao**. Imprimiam em stderr
e saiam 0. O README afirmava que o gatilho "torna a omissao impossivel de ser silenciosa" -
**refutado**: o gating seguiu tao silencioso quanto antes do hook existir.

## Por que a suite nao podia detectar

Todos os testes verificavam o que o hook **imprime**. Nenhum verificava o que o runtime
**entrega**. Sao coisas diferentes, e a diferenca e exatamente onde dois hooks morreram.

E o padrao ja tinha aparecido duas vezes:
- v2.0.1: `verify-gate` que nao disparava.
- v2.5.0: `output-budget` emitindo string onde o schema exigia objeto.

Ambos foram corrigidos como INSTANCIA. O ADR 0020 chegou a escrever "a licao nao havia sido
generalizada" - e nao a generalizou. Sinal degenerativo no sentido de Lakatos: correcao ad hoc
por sintoma, com a classe reaparecendo no artefato seguinte.

## Decisao

1. **Quem precisa AVISAR usa `additionalContext`. Quem precisa BLOQUEAR usa `exit 2`.**
   `stderr` com `exit 0` fica reservado a diagnostico que so o humano le no transcript.
2. **A suite ganha a assercao que faltava** (secao 12): para cada hook, verificar que ele usa
   um canal que entrega. Um hook novo que so escreva em stderr reprova a suite.
3. **Todo hook novo declara seu canal** no cabecalho, junto com o invariante.

## Os demais achados da 4a arguicao

| | Achado | Correcao |
|---|---|---|
| 2 | `sudo sh -c '... > "$HOME"/...'` grava em **/root**. `man sudoers`, conferido: com `env_reset` (default) "HOME... initialized based on the **target user**". Trocar `~` por `"$HOME"` nao corrigiu nada - quem expande e o mesmo shell de root. **Terceira reincidencia da classe** | Caminho ABSOLUTO, expandido pelo hook (que roda como usuario) |
| 3 | README publicava a autorizacao do Fable **sem `sudo`**. E `>` preserva o inode, entao o comando correto depois trunca sem trocar dono - negado para sempre, em silencio | `sudo` + caminho absoluto + aviso explicito para apagar antes |
| 4 | "100% de sobreposicao com o security-guidance" era **FALSO**: medido **9 de 11**. `exec(` em Python nao casa a regra nativa (`eval_injection` usa lookbehind) e `child_process` na forma `require` tambem nao. A desduplicacao removeu a explicacao sem que a substituta existisse | As duas lacunas REAIS recuperam explicacao propria; as outras nove seguem delegadas |
| 5 | `path_filter` e **chave inexistente** na API de usuario (a real e `paths`/`exclude_paths`); chave desconhecida e descartada em silencio, e a regra do Temporal disparava em `.md`. O `_comment` do arquivo afirmava "formato identico ao nativo" - foi essa premissa que produziu o erro | `paths` com globs; comentario corrigido; **harness commitado** (secao 14) |
| 6 | `settings.json` de referencia citava `ds4-notify.sh` 4x, e o arquivo **nao existe no repo**: quem instalasse levaria 4 `exit 127` por turno. A suite validava orfaos so em `hooks/hooks.json` - o arquivo que nao tinha o problema | Referencias removidas; **suite passa a varrer o `settings.json`** (secao 13) |
| 7 | Numeros publicados nao reproduziam pelo comando que o proprio README manda rodar. Assimetria reveladora: as linhas que MELHORARAM foram atualizadas; a que PIOROU ficou no valor antigo | `CLAUDE.md` 12.244 B (-73,6%), fixo 16.345 B (-71%), 12 hooks, ADRs 0001-0021 |
| 8 | O contrato de retorno era anunciado como universal e cobria 8 de 10. `implementador` e `tdd` ficavam de fora - **o agente que escreve codigo era o unico nao cobrado por evidencia** | Ambos entram, no hook e nos dois matchers |

## O que a arguicao CONFIRMOU

Sete das oito alegacoes verificaveis se sustentaram sob execucao: hooks PreToolUse disparam em
subagente (provado pelo proprio revisor ser bloqueado); `security-patterns.json` carrega e
funciona com controle negativo; `self-mod-audit` registra de fato; `medir-qualidade` e
conservador; **o corte de comentario da v2.6.0 preservou codigo IDENTICO nos quatro hooks** - o
ponto que eu mais temia; os -12% reproduzem; o teste de mutacao e genuino.

## Avaliacao arquitetural recebida, e o que ela muda

O revisor concluiu que **e um sistema, nao um monte de hooks**: principio unico instanciado em
tres mecanismos ortogonais (barreira, orcamento, roteamento), acoplamento baixo, sem dependencia
de ordem, fail-open/fail-closed correto onde importa. Nenhum hook faz duas coisas nao
relacionadas.

Mas identificou o furo estrutural: **nao faltava um hook, faltava uma ASSERCAO** - "o modelo
recebeu?". Sem ela, cada arguicao corrigia a instancia e a classe reaparecia. E o que a secao
12 da suite passa a cobrir, e e a razao de este ADR ser de contrato e nao de correcao.

## Estado

Suite **76/76**. Todos os 13 hooks usam canal que entrega, verificado por assercao permanente.
Nao verificado: `sudo sh -c 'echo $HOME'` nao foi executado (pede senha) - o achado 2 se apoia
na documentacao primaria do `sudoers`, conferida no `man`.
