#!/usr/bin/env python3
"""Cria uma fixture cujo NOME contem substituicao de comando.

Existe como arquivo proprio porque escrever esse nome via redirect do shell dentro do teste e
fragil - o proprio ato de criar a fixture vira um problema de quoting. Python escreve o nome
literalmente. O payload NAO pode conter '/', que e invalido em nome de arquivo; por isso o
marcador e relativo e o teste roda o executor com cwd no diretorio da fixture.

Uso: make_hostile_fixture.py <dir> <nome-do-marcador-sem-barra>
Imprime o caminho do arquivo criado.
"""
import pathlib
import sys

directory, marker = sys.argv[1], sys.argv[2]
assert "/" not in marker, "o marcador precisa ser um nome relativo, sem barra"
target = pathlib.Path(directory) / f"$(touch {marker}).csv"
target.write_text("a,b\n1,2\n")
print(target)
