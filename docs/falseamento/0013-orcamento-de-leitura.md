# ADR 0013 - Orcamento de leitura para arquivo grande, documento e midia

- Data: 2026-07-31
- Status: aceito

## Contexto

Ler um arquivo grande inteiro nao e apenas caro - piora a resposta. Modelos frontier degradam
conforme a entrada cresce, e o mecanismo nao e so custo: conteudo irrelevante porem
semanticamente proximo compete por atencao com o relevante (interferencia de distrator), e a
informacao no meio do contexto e recuperada com acuracia menor que a do inicio e do fim.
Despejar um log de 50 mil linhas nao "da mais contexto": dilui o sinal.

O padrao correto e sempre o mesmo - **localize, depois leia a faixa** - e ele nao era enforcado.

## Decisao

`read-budget.sh`, PreToolUse com matcher `Read`. Barra a leitura acima do orcamento e devolve a
RECEITA pronta, montada com as ferramentas verificadas neste box em tempo de execucao.

- Leitura ja dirigida (`offset`, `limit` ou `pages`) passa sem questionamento.
- PDF acima de 25 paginas -> `pdftotext -layout` e depois `grep`/`sed`; `pdftoppm` so quando o
  layout visual importa de fato.
- Office -> `pandoc` ou `libreoffice --headless`.
- Planilha -> agregar com `pandas` (shape, dtypes, describe) antes de olhar linha.
- CSV acima de 500 linhas -> perfilar antes.
- Texto acima de 4.000 linhas ou 300 KB -> `rg -n` e depois faixa; para log, `tail` e busca por
  padrao de erro.
- Imagem acima de 2 MB -> reduzir com `ffmpeg` (resolucao alem do necessario e token sem ganho).
- Video -> extrair quadros com `ffmpeg`.
- Binario e compactado -> listar conteudo, nao ler.
- **Audio -> declarar a limitacao.** Nao ha transcritor local neste box (`whisper` e
  `whisper-cpp` ausentes). O hook diz isso explicitamente em vez de deixar o modelo improvisar
  uma "leitura" de audio que nao aconteceu.

Fail-open: sem `jq`, sem caminho, arquivo inexistente ou dentro do orcamento, sai 0.

## Verificacao executada

10 de 10 casos: permite arquivo pequeno; barra log de 9.000 linhas com receita de `tail`/`rg`;
permite leitura com `offset`/`limit`; barra CSV de 900 linhas mandando agregar; barra audio
declarando a ausencia de transcritor; barra PDF de 300+ paginas mandando extrair texto.

## Limite honesto

O orcamento e heuristico (linhas e bytes), nao uma medida de entropia ou de relevancia. Um
arquivo de 5.000 linhas cuja leitura integral fosse de fato necessaria sera barrado, e o modelo
tera de pedir faixas - custo aceitavel diante do caso comum, que e o despejo desnecessario.
