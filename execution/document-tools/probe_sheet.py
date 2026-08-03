#!/usr/bin/env python3
"""Probe barato de planilha: responde o que decide o plano, sem ler o conteudo todo."""
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
out = {"path": str(p), "size_bytes": p.stat().st_size, "untrusted": True}
try:
    import pandas as pd
    if p.suffix.lower() in (".csv", ".tsv"):
        sep = "\t" if p.suffix.lower() == ".tsv" else ","
        head = pd.read_csv(p, sep=sep, nrows=200)
        out.update(kind="delimited", sheets=[None], columns=list(map(str, head.columns)))
        with p.open("rb") as fh: out["approx_rows"] = sum(1 for _ in fh) - 1
    else:
        xl = pd.ExcelFile(p)
        out.update(kind="workbook", sheets=xl.sheet_names)
        # data_only por padrao no pandas: formula nao e avaliada, so o valor cacheado
        out["columns"] = list(map(str, pd.read_excel(p, sheet_name=xl.sheet_names[0], nrows=50).columns))
except Exception as e:
    out["gap"] = {"kind": "probe_failed", "detail": str(e)[:200]}
print(json.dumps(out))
