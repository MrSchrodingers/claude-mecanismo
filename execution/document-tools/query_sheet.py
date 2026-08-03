#!/usr/bin/env python3
"""Filtra e devolve SO o recorte, com o indice da linha como ancora. Nunca o dataframe todo."""
import sys, pathlib
p, term = pathlib.Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else ""
import pandas as pd
d = (pd.read_csv(p, sep="\t" if p.suffix.lower()==".tsv" else ",")
     if p.suffix.lower() in (".csv",".tsv") else pd.read_excel(p))
if not term:
    print("termo ausente: informe o que localizar"); sys.exit(2)
m = d.apply(lambda r: r.astype(str).str.contains(term, case=False, na=False).any(), axis=1)
hit = d[m]
print(f"linhas que casam com '{term}': {len(hit)} de {len(d)}")
if len(hit):
    print("\nprimeiras 20 (indice = ancora na planilha):")
    print(hit.head(20).to_string())
