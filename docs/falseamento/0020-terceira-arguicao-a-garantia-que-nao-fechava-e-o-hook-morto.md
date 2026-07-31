# ADR 0020 - Terceira arguicao: a garantia que nao fechava e o hook que nunca rodou

- Data: 2026-07-31
- Status: aceito
- Corrige: 0016 (premissa central falsa), 0017 (mecanismo inerte)
- Veredito recebido: **revisar-e-ressubmeter** (falha estrutural nos dois ADRs)

Arguicao feita sobre **snapshot congelado** (`2b61c1f`), atendendo a objecao de alvo movel da
rodada anterior. O repo vivo seguiu mudando em paralelo, e isso foi declarado no escopo.

## B1 - A premissa central do ADR 0016 era FALSA

O ADR afirmava: *"comando AUTO-DETECTADO nao precisa de aprovacao: ele e construido por este
script, nao lido do disco do projeto."*

O **comando** era construido pelo script. O **codigo que ele executa** vinha do repositorio.
Quatro repros executados, em `$HOME` isolado, nenhum com `.claude/verify-cmd`:

| Rota | Gatilho | Comando gerado | Resultado |
|---|---|---|---|
| `tests/conftest.py` | so existir o diretorio `tests/` | `python3 -m pytest` | **marcador criado** |
| `package.json` `scripts.test` | `pkg_script test` | `npm test` | **marcador criado** |
| `manage.py` | arquivo presente | `python3 manage.py check` | **marcador criado** |
| `node_modules/.bin/tsc` | `tsconfig.json` | `npx --no-install tsc` | **marcador criado** |
| `build.rs` | `Cargo.toml` | `cargo check` | rota por construcao |

**A superficie tinha AUMENTADO, nao diminuido.** Antes exigia um arquivo `.claude/verify-cmd`;
depois bastava um diretorio `tests/` com um `conftest.py`, que o pytest importa sozinho.

Correcao: a auto-deteccao passa a produzir **apenas analisadores que nao executam codigo do
projeto** - `ruff check --isolated` (parsing puro, ignora a config do repo, sem plugin) e
`go vet`. Tudo que carrega codigo do projeto - suite de teste, script de `package.json`,
framework, `build.rs` - exige a mesma aprovacao de root do `.claude/verify-cmd`.

**Custo declarado, e ele e alto:** por default o gate faz lint, nao roda a suite. Rodar a suite
passa a exigir um ato explicito do usuario. E menos gate do que a v2.2 prometia - mas a v2.2
comprava aquele alcance com execucao drive-by de codigo de terceiro, que nao e preco que se
pague em silencio.

Verificado: os tres repros reproduziveis nesta maquina agora nao criam marcador.

## B2 - O `output-budget.sh` nunca cortou um byte

O hook emitia `updatedToolOutput` como **string**. O schema do runtime para a ferramenta Bash e
**objeto**: `BashOutput { stdout: string; stderr: string; interrupted: boolean }`
(`sdk-tools.d.ts:2663`, conferido na fonte). O runtime rejeitava com *"expected object,
received string"* e a saida original passava intacta.

Os "-94%" publicados mediam **o stdout do hook isolado**, nunca o efeito no contexto. E a mesma
classe do `verify-gate` que nao disparava (v2.0.1) - a licao nao havia sido generalizada.

E a suite nao pegava **e nao podia pegar**: a secao 11 validava o JSON do proprio hook contra
ele mesmo. Teste tautologico.

**Verificacao E2E, a que faltava.** Nao contra o stdout do hook, mas contra o que o modelo
recebe. Com o hook ativo, `seq 1 3000` retornou:

```
1..60
[... linhas 61-2959 elididas; nenhuma linha de erro/falha nelas ...]
2961..3000
[orcamento de saida: original 13892 B / 2999 linhas, limite 12000 B ...]
```

O runtime aceitou o objeto e o corte ocorreu de fato.

**Regra adotada:** hook que altera estado do runtime exige teste E2E contra o BINARIO, nunca
contra a propria saida.

### Tres defeitos encontrados DENTRO da correcao do B2

O hook reescrito ficou inerte de novo, por outros motivos, e cada um so apareceu por execucao:

1. **`case "$OUT" in *$'\x00'*)`** - bash nao armazena NUL em variavel, entao `$'\x00'` expande
   para string VAZIA e o padrao vira `**`, que casa com tudo. O hook saia no primeiro `case`,
   sempre. Um escape invisivel desligou o mecanismo inteiro; so `bash -x` mostrou.
2. **`grep -inE` perdeu o `-i`** na reescrita: `ERROR` maiusculo parou de casar e a preservacao
   de veredito morreu em silencio - o hook cortava o meio E descartava o erro que estava nele.
3. **Rodape colado na ultima linha** (`3000[orcamento...`): a substituicao de comando remove o
   `\n` final, e o rodape corrompia justamente a ultima linha, onde costuma estar o veredito.

## Achados GRAVES

| | Achado | Correcao |
|---|---|---|
| G1 | O gate deixou de verificar o proprio repo: `.claude/verify-cmd` sem aprovacao caia em `pytest` -> `exit 5` ("no tests ran") -> barrava, enquanto a suite real estava verde. Realizava literalmente o risco que o proprio codigo declara ("gate que acusa sem motivo e desligado pelo usuario") | Resolvido pelo B1: a auto-deteccao agora roda `ruff`, que passa |
| G2 | A instrucao de aprovacao impressa pelo hook estava **sem `sudo`**. Seguida literalmente, cria a lista com dono errado - e `append` nao muda dono, entao o comando correto tambem falha depois, em silencio, para sempre. Recorrencia literal do defeito corrigido em v2.1.1 | Instrucao agora usa `sudo sh -c` com `chown`, e avisa sobre o append |
| G3 | O teste de seguranca era **tautologico**: passava contra o mutante. O hash da suite incluia o `\n` final; o do hook (`sed -n 1p`) nao. O unico obstaculo era o hash errado, nao a posse de root | Hash alinhado + **teste de mutacao** permanente: remove a checagem de posse e exige que o payload PASSE a executar |

## MEDIOS e MENORES

`M1` decisao 4 do ADR 0016 sem teste algum -> tres casos adicionados (Write, Bash, leitura).
`M2` `head -25` descartava veredito em silencio -> agora declara quantos ficaram de fora.
`M3` saida de linha unica INFLAVA +101% -> corte por byte quando ha poucas linhas.
`M4` 500 KB morria com `E2BIG` e emitia 0 byte -> `--rawfile`.
`M5` sem `sha256sum`, `CH` vazio e `grep -qF ""` casava com qualquer lista -> **fail-closed**.
`M6` `skipDangerousModePermissionPrompt` citado como agravante era **non sequitur** - o
`sh -c` do hook nao passa pelo sistema de permissao em modo algum. Removido: inflar severidade
com fator irrelevante e falso-rigor dentro de um ADR de seguranca.
`m1` hash sem ancora casava dentro de token maior -> ancorado.
`m2` numeros de linha do trecho elidido eram relativos ao MEIO, e a instrucao "reexecute com
`sed -n X,Yp`" citava a linha errada -> absolutos.
`m3` byte NUL descartado em silencio -> saida binaria nao e cortada.
`m4` `stdout` e `stderr` fundidos -> separados.
`m6` "recuperacao comprovadamente pior no meio" sem fonte, numa afirmacao que MUDA a decisao
de desenho -> marcado `[nao verificado]`.
`m8` atribuicao a Check Point Research nao confirmada na fonte alcancavel (a referencia do NVD
e o GHSA) -> registrado como nao confirmado. O CVSS 8.7 e o "corrigido em 1.0.111", esses,
foram confirmados na NVD pelo revisor.

## O que o revisor CONFIRMOU

- CVE-2025-59536: CVSS 8.7 e "versions before 1.0.111", **na NVD**.
- RFC `anthropics/claude-code#45427`: existe, titulo casa com o uso.
- Posse de root resiste a symlink, hardlink (`fs.protected_hardlinks=1`) e user-namespace.
- **A medicao de tokens generaliza.** Recalculada sobre **40 transcripts independentes,
  190,4 MB**: `assistant/text` = **4,8%** agregado (faixa 0,8%-10,3%), superficie de ferramenta
  43,7%, attachment 19,9%. A objecao "amostra de uma sessao atipica" nao procede para a
  conclusao. Os numeros ESPECIFICOS do ADR eram de sessao atipica (`tool_use` 26% > `tool_result`
  21%; no agregado inverte para 11,1% e 32,6%) - o que **reforca** agir no `tool_result`.

## Sinal degenerativo, e o que ele exige

G2 e G3 sao recorrencias literais de defeitos corrigidos nos **dois commits imediatamente
anteriores** (v2.1.1: instrucao publicada nao executada; v2.3.0: fixture escrito contra a
suposicao da implementacao). Tres versoes, tres vezes a mesma classe.

Isso pede regra de metodo, nao a correcao N+1:

1. **Toda instrucao publicada ao usuario e EXECUTADA literalmente antes de ser publicada.**
2. **Todo teste de garantia de seguranca e validado por MUTACAO** - remove-se a garantia e
   exige-se que o teste reprove. Teste que sobrevive ao mutante nao testa a garantia.
3. **Hook que altera estado do runtime exige E2E contra o binario.**

## Falha de gating, de novo

O diff que criou o caminho de execucao lida do repositorio nao passou pelo `auditor-seguranca`,
embora a regra do `CLAUDE.md` o exigisse. A pergunta do ADR 0016 - *"de onde vem o dado que
isto consome?"* - foi feita para `.claude/verify-cmd` e **nao** para `conftest.py`. O agente que
a faria por oficio nao foi acionado. Terceira ocorrencia registrada.

## Estado

Suite 67/67. B1 fechado com repro; B2 verificado E2E ao vivo; G1/G2/G3 e todos os M/m tratados.
Nao verificado: a rota `cargo check`/`build.rs` (sem toolchain Rust default nesta maquina) -
classificada por construcao, nao por repro.
