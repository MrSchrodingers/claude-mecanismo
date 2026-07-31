# ADR 0006 - Medicao do gate anti-erro-obvio (telemetria + incident-log)

- Data: 2026-06-17
- Status: Aceito
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0005 (validacao de tese / varredura de erro obvio; poka-yoke C2/C8)

## Contexto

O ganho do gate anti-erro-obvio era, ate aqui, ANALOGIA NAO MEDIDA: a evidencia forte
(cirurgia, aviacao, NASA, Toyota) e de outros dominios; a eficacia em agente de IA era
plausivel, nao medida (pendencia explicita do ADR 0005). O usuario pediu para medir.

## Decisao

Dois instrumentos, separados de proposito porque medem classes diferentes com confianca
diferente - fundi-los seria desonesto:

1. **Telemetria automatica do poka-yoke (C2/C8).** O hook `poka-yoke-lint.sh` registra cada
   bloqueio em `~/.claude/logs/poka-yoke-lint.log` (TSV: ts ISO, arquivo, achado), FAIL-SAFE
   (log que falha nao quebra o hook). Relatorio: `scripts/colegio-metrics.sh` agrega por
   regra/extensao/dia. Deterministico e automatico.

2. **Incident-log manual (classe semantica).** `docs/metrics/erro-obvio-incidentes.md` -
   o usuario registra cada erro obvio que escapou (C1/C3/C5/C6/C7/C9/C10), taxonomizado por
   C-item, se o gate rodou, se chegou a prod, e por que escapou.

## Limites honestos (lente do Analista de Dados - nao fabricar numero)

- **Sem baseline retrospectivo.** Nao ha historico instrumentado do "antes". Logo NAO existe
  before/after retrospectivo; e medicao PROSPECTIVA (da instalacao em diante). Qualquer
  numero de "reducao %" retrospectivo seria inventado.
- **[1] mede o subconjunto FACIL.** Deadcode/sintaxe sao mecanizaveis, mas provavelmente NAO
  sao a classe que causou os problemas relatados (esses foram semanticos: IDOR, sucesso nao
  testado, requisito errado). Contar bloqueios do poka-yoke != "problemas evitados" - alguns
  o modelo corrigiria sozinho (afirmacao do consequente). Mede "erro de codigo capturado na
  fonte", nada alem.
- **[2] mede a classe que DOI, mas depende do usuario.** O erro semantico nao e regex-avel; so
  ha dado se o operador registrar cada escape. O instrumento estrutura o registro; nao o
  automatiza.
- **O ganho real** so deixa de ser analogia quando [2] acumula dados e a TENDENCIA cai ao
  longo do tempo. E o unico criterio falseavel de que o gate funciona na pratica.

## Validacao

Hook loga o bloqueio (verificado: escrever .py com import nao usado gera 1 linha no log E
exit 2); relatorio agrega o log e o incident-log; template de incidente com exemplo + taxonomia.

## Corroboracao empirica (2026-06-23, ref: docs/research/referencias-pesquisa-agentes-llm.md)

- Conteudo nao-acionavel dilui atencao; medir/comprimir muda a qualidade funcional: SkillReducer (arXiv:2603.29919). Reforca o valor de medir o gate.
- VALIDACAO DE PRODUCAO: ate 2026-06-23 o poka-yoke registrou 3 capturas reais em codigo de projeto (F841 var nao usada, F821 nome indefinido, F401 import nao usado) - evidencia direta de que a barreira mecanizada C2/C8 funciona em sessao real, nao so em teste. Limite mantido: medicao prospectiva, sem baseline retrospectivo.
