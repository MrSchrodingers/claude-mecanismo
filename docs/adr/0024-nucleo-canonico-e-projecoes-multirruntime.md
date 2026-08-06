# ADR 0024 — Núcleo canônico e projeções multirruntime

- Status: aceito
- Data: 2026-08-06

## Contexto

Copiar manualmente configuração para Claude Desktop, Claude CLI e Codex criaria três estados desejados independentes e sem convergência.

## Decisão

Manter fonte canônica em `execution/` e `orchestration/` e gerar projeções Claude e Codex, documentação e grafo executável. O renderizador possui modo de convergência e `--check`.

## Restrições

- leitura pode ser paralela; escrita é serial;
- `tdd` e `implementador` são escritores isolados;
- autor não certifica;
- correção limitada a duas rodadas;
- estado local máximo `CANDIDATE`;
- `verify-pr` continua certificação externa.

## Consequências

Portabilidade auditável e menor drift, com custo de tornar o renderizador crítico e exigir atualização quando runtimes mudarem. Equivalência sintática não prova equivalência comportamental.
