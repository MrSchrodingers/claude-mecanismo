# Prompt de abertura - sessao de fechamento da Fase 1

Cole o bloco abaixo como primeira mensagem de uma sessao limpa, com `cwd` em `~/evidence-gate`.

---

```
Sessao de fechamento da Fase 1 do evidence-gate (M2 -> M3).

LEIA PRIMEIRO, NESTA ORDEM, E NAO COMECE ANTES:
  docs/HANDOFF.md                 - contrato de teste, rigor exigido, armadilhas ja pagas
  docs/status.generated.md        - estado por execucao real (nunca digite contagem a mao)
  docs/adr/0022-*.md              - a decisao central e os 6 adendos de refutacao

ESTADO DE PARTIDA (confirme antes de tocar em qualquer coisa):
  bash scripts/status.sh --check      # deve sair 0
  bash install/verify.sh              # deve sair 0, sem orfaos
  gh run list --limit 1               # ultimo commit deve estar success
Se algum falhar, o primeiro trabalho e entender por que - nao contorne.

ESCOPO DESTA SESSAO, em ordem. Feche o que der; declare o que nao der.

P0.1  Confirmar o runtime efetivo. EU (usuario) vou rodar `/hooks`, `/status` e `--debug` e
      colar a saida - sao comandos do CLI, voce nao consegue executa-los. Registre
      desired/installed/loaded/executed/governed_by. O ADR 0022 diz que uma precedencia
      diferente entre hooks de usuario e plugins REFUTARIA parte do diagnostico central.
      Se refutar, corrija o ADR antes de seguir.

P0.2  Claim ledger em evidence/claims/*.yaml, com validador de schema e caso na CI.
      Schema no HANDOFF secao 5. Regra: referencia evidencia existente, nao duplica. O
      validador precisa reprovar se uma claim citar regressao ou mutante inexistente.
      Comece pelas claims que ja tem evidencia: G1..G11, D1..D5, S1..S6, R1..R4, MI1.

P0.3  Base de comparacao sem upstream. Hoje: commit local sem @{u} some do conjunto de
      mudancas e o gate fica inerte. Reproduza primeiro, depois corrija, depois mutante.

P0.4  Property-based testing sobre substituicao de placeholders do doctool.sh, filenames
      hostis, normalizacao de path e identidade do manifesto.

P1    Required status check + ruleset sem bypass. EU faco no GitHub; me diga exatamente o
      que configurar e como verificar depois. So depois disso o README pode dizer
      "enforcement" - antes, e feedback.

P2    Raiz de confianca (managed settings + allowManagedHooksOnly). EXIGE SUDO MEU.
      ARMADILHA: allowManagedHooksOnly desliga TODO hook de escopo de usuario de uma vez.
      Migre os 14 hooks para plugin force-enabled ANTES, verifique, so entao ative. Se nao
      der para migrar com seguranca nesta sessao, NAO ative - declare e pare.

FORA DE ESCOPO, e nao finja o contrario: corpus de eficacia (P4, semanas), auditoria
autoralmente independente (P5, exige terceiro), metodos formais (sem gatilho - ver HANDOFF),
grafos evidence-grade.

RIGOR - o que reprova esta sessao:
  1. Reproduza antes de corrigir. Sem repro com saida colada, nao ha defeito - ha suposicao.
  2. Corrija a CLASSE, nao a instancia.
  3. Todo teste novo passa por mutacao, e o kill precisa ser atribuivel ao caso-alvo.
     Mutante nao aplicado e FALHA, nao sobrevivencia.
  4. EXPECTED fixo. Nunca reduza o esperado para acomodar um SKIP.
  5. Dependencia de ORACULO ausente = exit 2 / NOT_VERIFIED. Variacao de AMBIENTE = SKIP,
     mas com assercao-guarda exigindo ao menos uma variante exercitada.
  6. Fonte primaria para todo fato externo. Quatro erros da sessao anterior foram afirmacao
     sem conferir a fonte.
  7. Sem execucao colada com exit code, o estado e NAO VERIFICADO. Diga isso.
  8. Uma suite por vez: elas nao sao reentrantes (G10 escreve manifest.lock e ~/.claude).

CRITERIO DE PRONTO - nao encerre sem colar:
  [ ] scripts/status.sh --check -> 0
  [ ] install/verify.sh -> 0, sem orfaos
  [ ] as 5 suites unitarias e os 2 runners de mutacao -> 0
  [ ] CI verde no commit final, com SHA e URL
  [ ] docs/status.generated.md regenerado e committado
  [ ] ADR novo ou adendo com o que foi feito E o que nao foi
  [ ] cada item P0/P1/P2 marcado: fechado / nao fechado / bloqueado por acao minha

PORTAO FINAL, obrigatorio: delegue ao agente `refutador` com o `git diff` cru da sessao
inteira. Contexto separado, instrucao para tentar refutar, nao para aprovar. Relate o
RACIOCINIO dele, nao so o veredito. A sessao anterior nao pode acionar esse portao por
restricao do ambiente e declarou a lacuna - esta deve fechar.

Comece confirmando o estado de partida e me diga o que encontrou antes de mudar qualquer coisa.
```

---

## Por que o prompt tem esta forma

- **Ordem de leitura explicita**: o HANDOFF contem o contrato de teste que impede as cinco
  formas de verde vacuo. Comecar sem ele e repetir os defeitos ja pagos.
- **Estado de partida verificado antes de mudar**: se o repositorio ja estiver divergente, a
  primeira tarefa muda.
- **Separacao do que exige o usuario**: `/hooks`, ruleset e sudo nao sao executaveis pelo
  agente. Prometer fecha-los seria declarar pronto o que nao foi feito.
- **Fora de escopo nomeado**: corpus e auditoria nao cabem numa sessao, e dizer o contrario
  seria a classe de defeito que este projeto existe para impedir.
- **Portao final no refutador**: a sessao anterior nao pode aciona-lo e declarou a lacuna.
