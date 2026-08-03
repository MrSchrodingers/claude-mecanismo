#!/usr/bin/env python3
"""AGREGA antes de olhar linha: shape, dtypes, nulos e describe cabem em poucas linhas e
respondem a maioria das perguntas. Despejar linhas em contexto e o erro caro."""
import sys, pathlib
p = pathlib.Path(sys.argv[1])
import pandas as pd
pd.set_option("display.max_columns", 40); pd.set_option("display.width", 160)
d = (pd.read_csv(p, sep="\t" if p.suffix.lower()==".tsv" else ",")
     if p.suffix.lower() in (".csv",".tsv") else pd.read_excel(p))
print(f"shape: {d.shape[0]} linhas x {d.shape[1]} colunas")
print("\ndtypes:"); print(d.dtypes.to_string())
n = d.isna().sum(); n = n[n > 0]
print("\nnulos por coluna:"); print(n.to_string() if len(n) else "  nenhum")
print("\ndescribe:"); print(d.describe(include="all").T.head(30).to_string())
