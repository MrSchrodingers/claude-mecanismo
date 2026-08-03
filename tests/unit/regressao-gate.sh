#!/usr/bin/env bash
# Regressao do GATE DE CONCLUSAO. Cada caso reproduz um defeito MEDIDO, nao um sintoma.
#
# Regra do repositorio (docs/adr/0020): caso chamado "bug do throttle" nao vale nada se nao
# reproduzir o MECANISMO. Aqui cada caso monta o estado, executa o hook e exige o exit code.
#
# ESTADO ANTES DA CORRECAO (medido em 2026-08-03, claude-code 2.1.220):
#   G1 REPROVA - segunda parada com o mesmo codigo quebrado retornava 0
#   G2 REPROVA - stop_hook_active=true saia 0 em silencio (canal que nao chega ao modelo)
#   G3 REPROVA - bytes de arquivo untracked nao entravam na identidade
#   G4 REPROVA - monorepo verificava so o primeiro ecossistema que casava
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
GATE="$PWD/evidence/hooks/verify-gate.sh"
export CLAUDE_ADAPTERS_DIR="$PWD/execution/adapters/code"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# HOME isolado: o ledger/stamp do gate mora em $HOME. Sem isolar, o estado do usuario decide
# o resultado do teste - ja aconteceu neste repo (tests/unit/run.sh, cabecalho).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/logs"

novo_repo(){  # $1 = nome; ecoa o caminho
  local r="$TMP/$1"; rm -rf "$r"; mkdir -p "$r"; cd "$r"
  git init -q .; git config user.email t@t; git config user.name t
  echo "x = 1" > base.py; git add -A; git commit -qm base
  printf '%s' "$r"
}
gate(){ printf '{"stop_hook_active":%s}' "${1:-false}" | bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?; }

echo "== G1. falha em cache NAO vira sucesso na segunda parada =="
R=$(novo_repo g1)
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
rc1=$(gate false)
chk "primeira parada BARRA codigo quebrado" "$rc1" 2
rc2=$(gate false)
chk "segunda parada, MESMO snapshot quebrado, CONTINUA barrando" "$rc2" 2

echo "== G2. stop_hook_active nao pode virar verde silencioso =="
R=$(novo_repo g2)
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
rc=$(gate true)
chk "nao bloqueia (anti-loop preservado)" "$rc" 0
# canal: stderr com exit 0 NAO chega ao modelo (docs/adr/0021). Exige additionalContext.
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' "$TMP/out" 2>/dev/null)
chk "  entrega additionalContext (canal que chega)" "$([ -n "$ctx" ] && echo sim || echo nao)" "sim"
chk "  declara NAO VERIFICADO" "$(printf '%s' "$ctx" | grep -qi 'NAO VERIFICADO' && echo sim || echo nao)" "sim"

echo "== G3. identidade cobre BYTES de arquivo nao rastreado =="
R=$(novo_repo g3)
printf 'y = 2\n' > solto.py           # untracked, limpo
rc=$(gate false)
chk "codigo limpo passa" "$rc" 0
printf 'def g():\n    return indefinido\n' > solto.py   # MESMO nome, agora quebrado
rc=$(gate false)
chk "mudar BYTES do mesmo untracked reprova" "$rc" 2

echo "== G4. monorepo: todo ecossistema aplicavel e verificado =="
R=$(novo_repo g4)
echo '{}' > package.json; git add -A; git commit -qm pkg
printf 'const a = 1;\n' > servico.js                      # JS valido
printf 'def h():\n    return indefinido\n' > quebrado.py  # Python quebrado
git add -A
rc=$(gate false)
chk "JS valido nao mascara Python quebrado" "$rc" 2

cd /
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "regressao do gate verde" || echo "regressao do gate VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
