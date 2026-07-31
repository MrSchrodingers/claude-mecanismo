# ADR 0009 - Hook de gatilho de UI (saliencia da revisao de frontend) + snapshot de medicao

- Data: 2026-07-01
- Status: Aceito
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0006 (medicao do gate), 0008 (voz nos agentes), Diretriz 7 (gating)

## Contexto

Pergunta recorrente do usuario: a revisao de frontend (`revisor-frontend`) SERA obrigatoriamente
usada, do jeito que a voz do colegiado e usada a cada turno? Diagnostico honesto: a voz do chat e
confiavel porque o hook `colegio-operating-mode` (UserPromptSubmit) reinjeta o modo a CADA turno -
entrega DETERMINISTICA. Ja o gating do `revisor-frontend` era DISCIPLINA PURA: nenhum mecanismo
reinjetava o lembrete no momento em que um arquivo de UI e tocado. Assimetria real - a revisao de
frontend era MENOS garantida que a voz.

## Decisao

1. **Hook `frontend-review-reminder.sh`** (PostToolUse, `Write|Edit|MultiEdit|NotebookEdit`): ao
   tocar arquivo de UI (`.vue/.tsx/.jsx/.svelte/.astro/.css/.scss/.sass/.less/.styl`), injeta via
   exit 2 um lembrete de que a revisao de frontend (`revisor-frontend` / `/direcao-de-arte`) e
   obrigatoria antes de declarar pronto (WCAG 2.2, harmonia com o Design System, alinhamento).
   Throttle de ~15 min (anti-spam em edicao de varios componentes); FAIL-OPEN (sem jq / nao-UI ->
   exit 0). Eleva o GATILHO da revisao de frontend a mesma entrega deterministica do modo operacional.
2. **LIMITE honesto (inalterado):** o hook ENTREGA o lembrete de forma deterministica; NAO forca o
   spawn do subagente - nenhum hook alcanca isso. Fecha o furo do "esqueci em silencio"; nao torna a
   revisao mecanicamente forcada. "Obrigatorio" passa a significar "lembrado deterministicamente no
   gatilho", nao "forcado".
3. **Escopo:** so frontend por agora. O padrao (gatilho-de-diff -> lembrete de agente) pode ser
   generalizado a `auditor-seguranca`/`analista-fluxos` depois - medir a eficacia deste primeiro
   (evitar generalizar mecanismo nao validado, Diretriz 3.1).

## Snapshot de medicao (atualiza o ADR 0006 com dado REAL - 8 dias de uso, 2026-06-23 a 07-01)

- **poka-yoke (C2/C8, mecanico): 88 bloqueios REAIS** - 70 F401 (import morto), 12 F841 (variavel
  morta), 3 F821 (nome INDEFINIDO = bug real, nao so limpeza), + F403/F405/F541. O gate mecanico
  saiu da analogia para o DADO: capturou 88 erros obvios em codigo de producao antes do merge.
- **Memoria dos agentes: 299 arquivos** de conhecimento acumulado em 11 agentes (revisor-codigo 93,
  investigador 71, revisor-critico 53, cetico 34). Uso intenso e real; conhecimento institucional
  dos projetos do usuario.
- **Incident-log (classe SEMANTICA, manual): 0 registros.** A eficacia na classe que mais causa
  problema (requisito/regressao/IDOR - C1/C3/C6) segue SEM medida: registrar cada escape tem friccao
  e nao aconteceu. O limite honesto do ADR 0006 esta CONFIRMADO na pratica - o mecanico se prova
  sozinho (88 capturas); o semantico depende de alimentacao manual que os 8 dias nao produziram. Os
  299 arquivos de memoria dos agentes sao um registro PARCIAL de defeitos, fora do formato do
  incident-log.

## Validacao

Hook testado: UI -> exit 2 (lembrete); segundo toque em <15 min -> exit 0 (throttle); nao-UI (.py) ->
exit 0; sem file_path -> exit 0 (fail-open). Wired em `settings.json` e no `hooks.json` do plugin -
o ambiente passa a ter 4 hooks. Gate de erro obvio antes do commit.

## Adendo (2026-07-01): log automatico de achados semanticos pelo revisor-critico

Motivacao: o incident-log manual ficou em 0 - registrar cada escape tem friccao e nao aconteceu.
Para dar DADO a classe SEMANTICA sem depender de registro manual, o `revisor-critico` passa a LOGAR
automaticamente, APOS o veredito e FAIL-SAFE, cada falha de item semantico (C1/C3/C5/C6/C7/C9/C10)
que corresponda a um defeito real que ele pegou, em `~/.claude/logs/semantic-findings.log`
(TSV: ts, C-item, severidade, arquivo:linha, descricao). Falha de log jamais altera o veredito.

Distincao CRITICA (nao confundir, senao a metrica mente): isto mede CATCHES - o defeito semantico
PARADO no gate -, NAO escapes. O incident-log manual (`docs/metrics/`) segue sendo o unico registro
de ESCAPES (o que passou a prod). O `scripts/colegio-metrics.sh` agora reporta os TRES: [1] catches
mecanicos (poka-yoke), [1b] catches semanticos (revisor-critico), [2] escapes semanticos (manual).
Limite honesto: catch-data mede a FREQUENCIA e o TIPO da classe semantica (o que faltava), nao a
taxa de escape; e telemetria fail-safe que nao enviesa o desfecho calibrado.
