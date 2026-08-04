# Observacao - precedencia entre hooks de usuario e hooks de plugin

- Data: 2026-08-04
- Ambiente: Linux, `claude-code 2.1.220`, binario `claude.exe` sob nvm node v22.19.0
- Fecha: P0.1 do `docs/HANDOFF.md`
- Responde: a condicao de refutacao declarada em `docs/adr/0022` ("O que refutaria este ADR")

## A pergunta

O ADR 0022 declara que seu diagnostico central cai se `~/.claude` nao for o escopo efetivo -
por exemplo, se plugins instalados **sobrescrevessem** os hooks em tempo de execucao. Ate esta
data a precedencia nao havia sido observada, e o handoff registrava a premissa como aberta.

## A premissa do handoff que se mostrou parcialmente falsa

O handoff afirma que `/hooks`, `/status` e `--debug` "sao comandos do CLI, voce nao consegue
executa-los". Verificado:

- `/hooks` e `/status` sao comandos da TUI interativa - de fato nao executaveis por Bash;
- `--debug` e uma FLAG de linha de comando, executavel;
- e existe observavel mais forte que `/hooks`: `--include-hook-events` com
  `--output-format=stream-json` emite `hook_started` e `hook_response` com `hook_event`,
  `exit_code` e `outcome`. `/hooks` mostra o que esta CONFIGURADO; isto mostra o que EXECUTOU.

## Metodo

Duas fontes independentes de observacao, para que nenhuma conclusao dependa de um so canal:

1. eventos de hook do proprio runtime (`--include-hook-events`);
2. efeito colateral verificavel: `session-integrity.sh` escreve um heartbeat por execucao em
   `~/.claude/evidence/session-integrity.jsonl`.

O tratamento e um plugin-sonda carregado apenas para a sessao de teste, via `--plugin-dir`,
com hooks em `SessionStart`, `UserPromptSubmit` e `Stop` que gravam um marcador. Nada da
configuracao do usuario foi alterado.

### Reproduzir

```
# baseline
claude -p "responda exatamente: OK" --model claude-haiku-4-5-20251001 --tools "" \
  --no-session-persistence --output-format stream-json --include-hook-events --verbose \
  | jq -r 'select(.subtype=="hook_started") | .hook_event' | sort | uniq -c

# tratamento: o mesmo, acrescido de --plugin-dir <sonda>
```

## Predicao registrada ANTES do tratamento

Se hooks de plugin SOMAM: `SessionStart=3, UserPromptSubmit=5, Stop=4`, os tres marcadores da
sonda presentes, e o heartbeat do hook de usuario continua incrementando.
Se plugin SOBREPOE o escopo de usuario: o heartbeat NAO incrementa.

## Medido

Declarado em `~/.claude/settings.json` (escopo de usuario): SessionStart 1, UserPromptSubmit 3,
Stop 2. Declarado pelo plugin `security-guidance@claude-plugins-official`: SessionStart 1,
UserPromptSubmit 1, Stop 1, PostToolUse 6. `settings.local.json` nao declara hooks.

| Execucao | SessionStart | UserPromptSubmit | Stop | heartbeat |
|---|---:|---:|---:|---|
| baseline | 2 | 4 | 3 | 1 -> 2 |
| com a sonda (`--plugin-dir`) | 3 | 5 | 4 | 2 -> 3 |

Marcadores da sonda no tratamento: `PLUGIN SessionStart`, `PLUGIN UserPromptSubmit`,
`PLUGIN Stop` - os tres. Todos os `hook_response` com `exit_code=0`, `outcome=success`.

## Conclusao

**Hooks de plugin SOMAM aos de escopo de usuario; nao os sobrepoem.** O total executado por
evento e a UNIAO dos escopos, filtrada pelo `matcher`. A aritmetica fecha exatamente nos dois
sentidos: usuario + plugin = observado, no baseline e sob tratamento.

A condicao de refutacao do ADR 0022 **nao se realizou**. O diagnostico central permanece de pe,
agora com premissa medida em vez de aberta.

## Verificacao cruzada com `matcher`

Numa execucao que usou a ferramenta Bash: `PreToolUse=1` (o `fable-guard`, unico com matcher
`Agent|Task|Bash|Workflow`) e `PostToolUse=1` (o `output-budget`, matcher `Bash`). Os 6
`PostToolUse` do `security-guidance` nao dispararam - matcher nao casou. Consistente com
"uniao filtrada por matcher", e nao com "todos os hooks do evento".

## Limites declarados

- Uma so versao do runtime (2.1.220) e uma so plataforma (Linux). Nao ha base para afirmar a
  mesma precedencia em outras versoes ou em macOS/Windows.
- Nao foi observado o comportamento sob `managed settings` com `allowManagedHooksOnly` - esse
  e o escopo do P2 e tem documentacao primaria propria.
- Ordem de execucao DENTRO de um mesmo evento nao foi medida; apenas o conjunto executado.
