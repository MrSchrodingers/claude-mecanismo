#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib, tomllib
ROOT=pathlib.Path(__file__).resolve().parents[1]

def fail(msg): print(f'PROJECTION_ERROR {msg}'); return 1

def main():
 p=argparse.ArgumentParser(); p.add_argument('--check',action='store_true'); p.parse_args()
 reg=json.loads((ROOT/'orchestration/registry.json').read_text())
 if reg.get('schema_version')!=1:return fail('schema_version')
 names=set(reg['agents'])
 for n,s in reg['agents'].items():
  if not (ROOT/s['source']).is_file(): return fail(f'fonte ausente: {n}')
  if not (ROOT/f'.claude/agents/{n}.md').is_file(): return fail(f'projecao Claude ausente: {n}')
  if not (ROOT/f'.codex/agents/{n}.toml').is_file(): return fail(f'projecao Codex ausente: {n}')
 for f in ['.claude/settings.json','.codex/config.toml','.codex/hooks.json','CLAUDE.md','AGENTS.md']:
  if not (ROOT/f).is_file(): return fail(f'arquivo ausente: {f}')
 tomllib.loads((ROOT/'.codex/config.toml').read_text())
 if not json.loads((ROOT/'.codex/hooks.json').read_text()).get('hooks'): return fail('hooks Codex vazios')
 for pth in sorted((ROOT/'orchestration/workflows').glob('*.json')):
  w=json.loads(pth.read_text()); nodes=set(w['nodes'])
  if w['entry'] not in nodes or any(a not in nodes or b not in nodes for a,b in w['edges']): return fail(f'grafo invalido: {pth.name}')
 if names!={p.stem for p in (ROOT/'.claude/agents').glob('*.md')}:return fail('inventario Claude diverge')
 if names!={p.stem for p in (ROOT/'.codex/agents').glob('*.toml')}:return fail('inventario Codex diverge')
 print(f'projeções verificadas: {len(names)} agentes, {len(list((ROOT/"orchestration/workflows").glob("*.json")))} workflows')
 return 0
if __name__=='__main__': raise SystemExit(main())
