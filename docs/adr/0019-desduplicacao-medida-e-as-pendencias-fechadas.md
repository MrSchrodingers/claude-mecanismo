# ADR 0019 - Desduplicacao medida, bypass de subagente testado, e as pendencias fechadas

- Data: 2026-07-31
- Status: aceito

## 1. Bypass de subagente: modo de falha nº1 da RFC NAO se aplica aqui

A RFC `anthropics/claude-code#45427` lista como falha nº1: *"Parent session hooks don't trigger
for subagent tool calls. A model blocked from editing files can dispatch a subagent that edits
freely."* Se verdadeiro neste runtime, metade das garantias desta config seria contornavel por
delegacao.

**Medido**, com uma sonda em PreToolUse e um subagente instruido a usar Write, Bash e Read:

```
chamadas PreToolUse capturadas na SESSAO PRINCIPAL: 24
chamadas PreToolUse capturadas em SUBAGENTE .....: 126
ferramentas vistas dentro de subagente: Write, Bash, Read, Edit
agent_type observados: general-purpose, refutador
```

**Hooks PreToolUse disparam dentro de subagente.** `artifact-discipline`, `read-budget`,
`output-budget` e `self-mod-audit` valem tambem la. A RFC pode estar correta para a versao em
que foi escrita; nao esta para esta. Sonda removida apos responder a pergunta.

## 2. Desduplicacao com o `security-guidance`, por medicao

O plugin oficial `security-guidance@2.0.6` (David Dworken, Anthropic) tem 25 regras nativas e
**dispara de fato** - verificado executando o hook dele com payload real.

Sobreposicao com a categoria EXEC do meu `risk-trigger.sh`, token a token:

```
os.system -> os_system_injection          eval( -> eval_injection
subprocess -> python_subprocess_shell     exec( -> eval_injection
shell=True -> python_subprocess_shell     pickle.loads -> pickle_deserialization
innerHTML -> innerHTML_xss                yaml.load( -> unsafe_yaml_load
dangerouslySetInnerHTML -> react_...      new Function( -> new_function_injection
child_process -> child_process_exec
SOBREPOSICAO: 11 de 11 = 100%
```

E a remediacao dele e mais especifica que a minha (`Use subprocess.run([...])`, `considere
DOMPurify`). Manter a minha era duplicar trabalho mais maduro.

**O que ele NAO cobre** (verificado - nenhum aviso emitido): segredo literal, IDOR/escopo do
dono (a familia A01), mudanca de lockfile, UI/WCAG, laco aninhado.

**Decisao:** a EXPLICACAO da vuln da familia EXEC passa a ser dele; o `risk-trigger` mantem so
o ROTEAMENTO (qual agente acionar), que ele nao faz. Nao removi a deteccao porque **o aviso
dele DECAI**: e emitido N vezes por regra por sessao e depois silencia
(`~/.claude/security_warnings_state_<id>.json`, anti-fadiga de alarme). Roteamento nao pode
decair - numa sessao longa, o ultimo diff arriscado precisa acionar o agente tanto quanto o
primeiro.

## 3. Padroes de dominio plugados, em vez de duplicados

`extensibility.py` do plugin le `security-patterns.{yaml,json}` com o MESMO formato das regras
nativas, ja com validacao e protecao anti-ReDoS. Criado `~/.claude/security-patterns.json` com
o que o nativo nao cobre e que importa neste stack:

| Regra | Cobre |
|---|---|
| `django_queryset_sem_escopo_do_dono` | A01: filtro por ID do request sem posse na MESMA query |
| `drf_serializer_mass_assignment` | `fields = "__all__"` |
| `ordenacao_ou_filtro_vindo_do_request` | `order_by`/`extra`/`raw` com dado do cliente |
| `segredo_literal_no_codigo` | lacuna confirmada do nativo |
| `temporal_activity_sem_idempotencia` | reexecucao de activity com efeito colateral |

**13/13 com controle negativo.** O ponto do controle negativo: a primeira versao do padrao A01
disparava tambem em `.filter(id=request.GET["pk"], owner=request.user)` - o codigo CORRETO.
Alarme que toca sempre e alarme que se aprende a ignorar, e ai o mecanismo custa sem proteger.
Corrigido com lookahead negativo sobre os termos de posse.

Nota de metodo: a primeira execucao da suite de padroes reprovou 3 de 13 contra um mecanismo
que funcionava - os casos anteriores haviam "consumido" o aviso pelo estado de sessao do
plugin. Isolar `session_id` por caso resolveu. Quarta vez nesta reforma em que um teste meu
quase condenou codigo correto.

## 4. `feature-dev` desligado

Os 3 agentes dele duplicavam os meus: `code-reviewer` ~ `revisor-codigo`, `code-explorer` ~
`mapeador-dependencias`, `code-architect` ~ `analista-otimalidade`. E o `code-reviewer` **nao
tem Bash**, entao nao roda linter - inferior no eixo que mais importa nesta config (executar em
vez de opinar). Duplicacao que eu mesmo criei ao habilitar o plugin sem examina-lo.

## 5. Auto-modificacao: DETECCAO, nao prevencao

Modo de falha nº3 da RFC, confirmado: `[ -w hooks/fable-guard.sh ]` e `[ -w settings.json ]`
sao ambos verdadeiros. O modelo pode desligar as proprias guardas.

`self-mod-audit.sh` registra toda escrita em `hooks/` e `settings.json` numa trilha duravel e
emite aviso de alta saliencia. **Nao previne, e dizer que previne seria falso rigor.** Prevenir
exigiria bloquear toda escrita nesses caminhos, o que tornaria a manutencao da config
impossivel sem desligar o hook - mecanismo que se desliga para trabalhar nao e mecanismo. A
solucao correta (tool gate dentro do CLI, com `protected: true`, fora do alcance do modelo) e o
que a RFC pede, e ela foi **fechada como not planned**. Nao ha primitiva. O melhor disponivel e
tornar o desligamento silencioso em desligamento visivel.

## 6. Citacao verificada na fonte primaria

O numero "541 violacoes em 300 UIs" estava marcado como nao verificado (paywall ACM). Obtido o
PDF na pagina do autor e extraido com `pdftotext` - o mesmo padrao que o `read-budget` ensina:

> "Analyzing 300 UIs produced by three commercial models, we identify 541 semantic violations"

Calo, Gurita e De Russis (Politecnico di Torino; Univ. Stefan cel Mare). Marca removida.

## 7. Medicao de qualidade: o que da para medir, e o que nao da

`scripts/medir-qualidade.sh` mede a taxa de conformidade ao contrato de retorno sobre trafego
REAL acumulado pela sonda. Estado atual: **9 retornos no escopo, 9 conformes (100%)**; 23 fora
do escopo, nao julgados.

Defeito corrigido no proprio script: a primeira versao contava agentes FORA do escopo
(`general-purpose`, `code-review`) como conformes, porque o hook sai 0 para eles. Isso inflava
a taxa de 100% sobre 9 para 100% sobre 32. **Contar nao-julgado como aprovado** e exatamente a
auto-ilusao que esta config existe para impedir, cometida no script criado para medi-la.

Limite declarado, e ele e o que importa: isto mede a **FORMA** do retorno (o bloco existe, a
ancora existe), nao o **MERITO** (a evidencia e boa? a conclusao esta certa?). Forma e
verificavel por maquina; merito nao. **Continua sem existir medicao de que esta config melhora
as respostas** - isso exigiria conjunto de tarefas com gabarito e A/B com e sem a config.
Enquanto nao houver, o ganho de qualidade e HIPOTESE.
