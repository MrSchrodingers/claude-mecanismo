# ADR 0017 - Onde os tokens realmente vao, e o orcamento de saida de ferramenta

- Data: 2026-07-31
- Status: aceito

## Medicao, antes da opiniao

Distribuicao real de bytes num transcript de sessao de trabalho (2,98 MB, 1.053 registros):

| Categoria | Bytes | % |
|---|---|---|
| `assistant/tool_use` (comandos que o modelo escreve) | 393.644 | **26%** |
| `user/tool_result` (saida desses comandos) | 321.405 | **21%** |
| `assistant/thinking` | 311.715 | 21% |
| `attachment` (re-injecao de arquivo apos edicao) | 221.697 | **15%** |
| `assistant/text` (a prosa para o usuario) | 70.470 | **4%** |

## A conclusao contra-intuitiva

A intuicao popular sobre economia de token mira a PROSA - respostas mais curtas, menos
explicacao. Medido: a prosa e **4%** do orcamento. Reduzi-la a metade economiza 2%, e paga esse
2% em perda de precisao argumentativa.

O orcamento real esta em **saida de ferramenta: 47%** (`tool_use` + `tool_result`). E o segundo
maior item isolado, `attachment` com 15%, e re-injecao de conteudo de arquivo apos edicao -
custo que o modelo controla escolhendo edicao dirigida em vez de reescrita de arquivo grande.

Consequencia de desenho: **estilo de comunicacao concisa e questao de QUALIDADE, nao de
economia.** Vale adotar porque sinal denso e melhor que prosa diluida - nao porque poupa token.
Quem quer economia de verdade age na saida de ferramenta.

## Decisao

`output-budget.sh`, PostToolUse com matcher `Bash`, usando `hookSpecificOutput.updatedToolOutput`
para reescrever o resultado antes que ele entre no contexto.

**O corte preserva CABECA e CAUDA, e elide o MEIO.** Nao e escolha estetica:
- em saida de comando, o inicio traz o contexto (comando, versao, primeiros erros) e o fim traz
  o veredito (ultimas falhas, resumo, exit code);
- o meio de uma listagem longa e a parte redundante;
- recuperacao de informacao em contexto longo e relatada como pior no meio que nos extremos
  (fenomeno conhecido como lost-in-the-middle) - **[nao verificado na fonte primaria nesta
  sessao]**. A afirmacao MUDA a decisao de desenho, entao ficaria sujeita ao C7; enquanto nao
  for conferida, o argumento se sustenta apenas nos dois primeiros itens, que sao suficientes.

**Nao corta o que carrega veredito.** Linhas com `error`, `fail`, `traceback`, `exception`,
`panic`, `denied`, `timeout`, `exit code` ou `assert` sao preservadas MESMO quando caem na
regiao elidida, e o hook sinaliza que as preservou. Perder um `FAILED` para economizar token
seria trocar qualidade por custo - o oposto do objetivo.

Limite default 12.000 B, ajustavel por `CLAUDE_OUTPUT_BUDGET`. Fail-open em qualquer erro.

## Verificacao executada

| Caso | Resultado |
|---|---|
| Saida abaixo do limite | nao altera nada |
| 2.000 linhas sem erro | 20.889 -> 1.234 B (**-94%**), cabeca e cauda preservadas |
| 2.000 linhas com `ERROR` na linha 900 (regiao elidida) | **linha preservada**; 20.938 -> 1.309 B |
| Input vazio / invalido / sem stdout | fail-open, sem alteracao |

Incorporado a suite (secao 11): 55/55.

## Limite honesto

O corte e heuristico (linhas e bytes, mais um regex de veredito), nao uma medida de relevancia.
Uma saida cujo conteudo essencial esteja no meio E nao case com o regex de veredito perde
informacao. Mitigacao: a elisao e sempre SINALIZADA com o tamanho original e a instrucao de
reexecutar o comando estreitado - o modelo sabe que foi cortado e sabe como recuperar.
Silenciar o corte seria o defeito grave; sinaliza-lo o torna recuperavel.
