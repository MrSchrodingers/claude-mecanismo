#!/usr/bin/env bash
# Mede USO REAL de skill a partir dos transcripts, para decidir criacao e depreciacao por
# evidencia em vez de intuicao.
#
# ARMADILHA QUE ESTE SCRIPT EXISTE PARA EVITAR - ja custou uma decisao errada:
# skill tem DOIS canais de invocacao, e eles aparecem de formas DIFERENTES no transcript:
#   1. modelo invoca  -> `tool_use` com name="Skill" e input.skill
#   2. usuario digita -> `/nome` no TEXTO do usuario; NAO gera tool_use algum
# Consultar so o canal 1 leva a concluir "nunca usada" sobre uma skill usada toda semana.
# Aconteceu: `defesa-de-tese` tinha 0 no canal 1 e 5 invocacoes no canal 2, e foi arquivada
# por engano.
#
# Uso: bash scripts/medir-skills.sh [dir-de-projetos] [dir-de-skills]
set -uo pipefail
PROJ="${1:-$HOME/.claude/projects}"
SKILLS="${2:-$HOME/.claude/skills}"

python3 - "$PROJ" "$SKILLS" <<'PY'
import json, pathlib, collections, re, sys

proj, skills_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

instaladas = sorted(d.name for d in skills_dir.glob('*') if (d / 'SKILL.md').exists())
tool_use = collections.Counter(); slash = collections.Counter()
sess = collections.defaultdict(set)
n_transcripts = 0

nomes = set(instaladas)
pat = re.compile(r'(?:^|\s)/(' + '|'.join(re.escape(n) for n in nomes) + r')\b') if nomes else None

for p in proj.rglob('*.jsonl'):
    if 'subagents' in str(p):
        continue
    n_transcripts += 1
    for line in p.open(errors='ignore'):
        d = None
        if '"Skill"' in line:
            try: d = json.loads(line)
            except Exception: d = None
            if d:
                m = d.get('message') or {}
                c = m.get('content') if isinstance(m, dict) else None
                if isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get('type') == 'tool_use' and b.get('name') == 'Skill':
                            s = (b.get('input') or {}).get('skill')
                            if s:
                                tool_use[s] += 1; sess[s].add(p.stem)
        if pat and '/' in line:
            if d is None:
                try: d = json.loads(line)
                except Exception: continue
            if d.get('type') in ('user', 'last-prompt', 'queued-command', 'queue-operation'):
                m = d.get('message') or {}
                c = m.get('content') if isinstance(m, dict) else None
                txt = c if isinstance(c, str) else (
                    ' '.join(b.get('text', '') for b in c if isinstance(b, dict)) if isinstance(c, list) else '')
                txt += ' ' + str(d.get('prompt', '') or '')
                for m2 in pat.finditer(txt):
                    slash[m2.group(1)] += 1; sess[m2.group(1)].add(p.stem)

def custo(nome):
    f = skills_dir / nome / 'SKILL.md'
    try:
        for ln in f.read_text(errors='ignore').split('\n'):
            if ln.startswith('description:'):
                return len(ln) - 13
    except Exception:
        pass
    return 0

print(f"transcripts varridos: {n_transcripts} | skills instaladas: {len(instaladas)}\n")
print(f"{'skill':32s} {'modelo':>7s} {'/cmd':>6s} {'total':>6s} {'sessoes':>8s} {'custo B':>8s}")
print('-' * 72)
linhas = []
for s in instaladas:
    t, u = tool_use[s], slash[s]
    linhas.append((t + u, s, t, u, len(sess[s]), custo(s)))
linhas.sort(reverse=True)
mortas = []
for tot, s, t, u, ns, c in linhas:
    marca = '' if tot else '   <- ZERO USO'
    print(f"{s:32s} {t:>7} {u:>6} {tot:>6} {ns:>8} {c:>8}{marca}")
    if tot == 0:
        mortas.append((s, c))

print()
if mortas:
    total_b = sum(c for _, c in mortas)
    print(f"CANDIDATAS A DEPRECIACAO: {len(mortas)} skills, {total_b} B de descricao por sessao")
    for s, c in mortas:
        print(f"  {s} ({c} B)")
    print()
    print("ANTES DE ARQUIVAR, verifique - zero uso NAO e prova de inutilidade:")
    print("  (a) a skill e nova? Nao houve tempo de uso.")
    print("  (b) o gatilho da `description` esta errado? Ela nunca dispara mesmo sendo util.")
    print("  (c) existe ARTEFATO no disco que ela produziria? Procure a saida, nao so a chamada.")
    print("  Depreciar por (b) e jogar fora capacidade por defeito de roteamento.")
else:
    print("nenhuma skill com zero uso.")
PY
