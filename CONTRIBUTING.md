# Contribuição

## Unidade de mudança

Cada pull request deve ter uma tese verificável e uma fronteira de escopo. Mudanças de
instalador privilegiado, autorização, supply chain, parser ou workflow de CI devem ser
separadas de refatorações editoriais sempre que a separação preservar o comportamento.

Prefira PRs pequenos o suficiente para revisão adversarial. Um PR grande deve justificar por
que a decomposição criaria estados intermediários inválidos ou destruiria a atribuição dos
testes.

## Contrato mínimo

Toda nova garantia deve incluir:

1. claim e limite explícitos;
2. reprodução ou observação que motive a mudança;
3. teste que falhe pelo motivo correto antes da correção;
4. caso de borda e controle negativo;
5. mutante atribuível quando a garantia for estrutural;
6. atualização do manifesto e das projeções geradas, quando aplicável;
7. execução local documentada e `verify-pr` verde no SHA final.

Use `NOT_VERIFIED` quando uma dependência, plataforma ou pré-condição impedir o experimento.
Não transforme ausência de tratamento em PASS.

## Fluxo recomendado

```bash
python3 orchestration/render.py
bash install/manifest.sh install/manifest.lock
python3 orchestration/render.py --check
bash tests/unit/runtime-ports.sh
bash tests/unit/managed.sh
bash tests/mutation/install.sh
bash scripts/status.sh
```

Execute também as demais suítes definidas em `.github/workflows/verify-pr.yml`.

## Commits e revisão

Use Conventional Commits em português do Brasil.

O implementador não certifica a própria mudança. Revisores devem examinar arquivos, comandos
e saídas reais. O estado final de uma sessão é `CANDIDATE`; merge depende do gate externo.
