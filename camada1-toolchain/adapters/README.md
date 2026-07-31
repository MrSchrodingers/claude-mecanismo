# Adaptadores de toolchain

Um arquivo por ecossistema. Adicionar suporte a uma linguagem e **adicionar um arquivo**, nunca
editar um hook. E o que separa a camada 1 (acoplada a ferramenta) da camada 0 (universal).

## Por que a distincao ANALISADOR vs EXECUTOR e a mais importante deste arquivo

Ela nao e taxonomia: e a correcao de uma vulnerabilidade real, com repro.

A versao anterior desta config auto-detectava o comando de verificacao e rodava `pytest`,
`npm test`, `manage.py check` ou `npx tsc` sem aprovacao, sob o argumento de que "o comando e
construido pelo hook, nao lido do projeto". **O comando era construido pelo hook; o CODIGO QUE
ELE EXECUTA vinha do repositorio.** Quatro repros criaram marcador em disco:

```
tests/conftest.py     pytest importa automaticamente     -> marcador criado
scripts.test          npm roda o script do package.json  -> marcador criado
manage.py             importa settings e apps do projeto -> marcador criado
node_modules/.bin     npx --no-install usa o binario do repo -> marcador criado
```

Classe do CVE-2025-59536 (CVSS 8.7, "versions before 1.0.111", confirmado na NVD): configuracao
de projeto controlada por repositorio levando a execucao de comando. Clonar um repo hostil e
editar um arquivo bastava.

Por isso cada adaptador separa:

| Campo | Semantica | Aprovacao |
|---|---|---|
| `analyzer` | **Le** o codigo como DADO. Nao importa, nao executa, nao carrega plugin do projeto. | automatico |
| `test` | **Executa** codigo do projeto | exige aprovacao de root |
| `audit` | Consulta base de CVE das dependencias | automatico (nao executa o codigo) |
| `security_lint` | Regras estaticas de seguranca | automatico |

Ao adicionar um ecossistema, a pergunta nao e "qual comando verifica?", e
**"este comando executa codigo que vem do repositorio?"**. Em duvida, e `test`.

## Armadilhas ja pagas, por linguagem

- **Python**: `ruff` precisa de `--isolated`, senao le `[tool.ruff]` do repo. `mypy` NAO entra
  como analyzer: `mypy.ini` pode declarar `plugins = <modulo do repo>`, que e execucao.
  `python3 -m pytest` (nao o binario `pytest`): o modulo insere o cwd em `sys.path`, o binario
  nao, e sem isso a coleta falha em repo sem packaging - erro de coleta seria lido como teste
  vermelho.
- **Node**: `npx --no-install` usa `node_modules/.bin` do repo. E executor, nao analisador.
- **Rust**: `cargo check` executa `build.rs`. Executor.
- **Go**: `go vet` faz analise estatica; nao roda o programa. Analisador.
- **C#/.NET**: `dotnet build` executa MSBuild targets do `.csproj`, que podem rodar tarefas
  arbitrarias. Executor. `dotnet format --verify-no-changes` e analisador.

## Formato

```json
{
  "ecossistema": "nome",
  "detect": ["arquivo ou glob que indica o ecossistema"],
  "analyzer": {"cmd": "...", "porque_nao_executa": "justificativa explicita"},
  "security_lint": {"cmd": "..."},
  "audit": {"cmd": "..."},
  "test": {"cmd": "...", "executa_codigo_do_repo": true},
  "extensoes": [".ext"]
}
```

`porque_nao_executa` e obrigatorio em `analyzer`. Um adaptador sem essa justificativa e
rejeitado pela suite - a justificativa e o ponto de revisao, nao burocracia.
