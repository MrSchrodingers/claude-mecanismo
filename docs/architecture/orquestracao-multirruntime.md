# Orquestração multirruntime

## Modelo

\[
Runtime_r = Core + Projection(Core,r)
\]

O núcleo vive em `execution/` e `orchestration/`; `.claude/`, `.codex/`, `.agents/skills/`, `CLAUDE.md` e `AGENTS.md` são projeções determinísticas.

## Invariantes

- agentes de leitura e avaliação podem ocorrer em paralelo;
- nenhum escritor participa de grupo paralelo;
- escrita é serializada;
- `tdd` precede `implementador`;
- revisão e refutação são posteriores à escrita;
- autor não certifica;
- no máximo duas rodadas de correção;
- estado terminal local `CANDIDATE`.

Formalmente, para qualquer grupo paralelo `G`, `sum writes(n)=0`.

## Workflows

`investigation-only`, `standard-change` e `high-risk-change` são definidos em JSON, renderizados em Mermaid e validados por testes.

## Fronteiras

Agentes Claude são projetados em `.claude/agents`; agentes Codex em `.codex/agents/*.toml`. Skills canônicas são espelhadas. Declaração de sandbox e worktree não é prova de isolamento de sistema operacional.

## Limites

Sem corpus comparativo, auditoria independente, sandbox real ou supply chain hermética. A convergência verificada é estrutural, não equivalência semântica universal.
