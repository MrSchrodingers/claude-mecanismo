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

# ARMADILHA JA PAGA: `R=$(novo_repo g3)` roda a funcao num SUBSHELL, e o `cd` morre com ele -
# os casos executavam no diretorio do caso anterior e reportavam PASS/FAIL por motivo errado.
# Por isso esta funcao muda o cwd do shell PRINCIPAL e nao ecoa nada.
novo_repo(){  # $1 = nome
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"; cd "$R" || exit 1
  git init -q .; git config user.email t@t; git config user.name t
  echo "x = 1" > base.py; git add -A; git commit -qm base
}
gate(){ printf '{"stop_hook_active":%s}' "${1:-false}" | bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?; }

echo "== G1. falha em cache NAO vira sucesso na segunda parada =="
novo_repo g1
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
rc1=$(gate false)
chk "primeira parada BARRA codigo quebrado" "$rc1" 2
rc2=$(gate false)
chk "segunda parada, MESMO snapshot quebrado, CONTINUA barrando" "$rc2" 2

echo "== G2. stop_hook_active nao pode virar verde silencioso =="
novo_repo g2
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
rc=$(gate true)
chk "nao bloqueia (anti-loop preservado)" "$rc" 0
# canal: stderr com exit 0 NAO chega ao modelo (docs/adr/0021). Exige additionalContext.
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' "$TMP/out" 2>/dev/null)
chk "  entrega additionalContext (canal que chega)" "$([ -n "$ctx" ] && echo sim || echo nao)" "sim"
chk "  declara o estado NOT_VERIFIED" "$(printf '%s' "$ctx" | grep -q 'NOT_VERIFIED' && echo sim || echo nao)" "sim"

echo "== G3. identidade cobre BYTES de arquivo nao rastreado =="
novo_repo g3
printf 'y = 2\n' > solto.py           # untracked, limpo
rc=$(gate false)
chk "codigo limpo passa" "$rc" 0
printf 'def g():\n    return indefinido\n' > solto.py   # MESMO nome, agora quebrado
rc=$(gate false)
chk "mudar BYTES do mesmo untracked reprova" "$rc" 2

echo "== G4. monorepo: todo ecossistema aplicavel e verificado =="
novo_repo g4
echo '{}' > package.json; git add -A; git commit -qm pkg
printf 'const a = 1;\n' > servico.js                      # JS valido
printf 'def h():\n    return indefinido\n' > quebrado.py  # Python quebrado
git add -A
rc=$(gate false)
chk "JS valido nao mascara Python quebrado" "$rc" 2

echo "== G5. tabela de adaptadores ausente e FAIL-CLOSED, nao inercia silenciosa =="
# Caso adicionado porque o mutante M5 SOBREVIVEU: a suite passava com o fail-closed removido.
novo_repo g5
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
VAZIO="$TMP/sem-adaptadores"; mkdir -p "$VAZIO"
SALVO="$CLAUDE_ADAPTERS_DIR"; export CLAUDE_ADAPTERS_DIR="$VAZIO"
rc=$(gate false)
chk "tabela vazia BARRA (gate desligado nao pode passar batido)" "$rc" 2
chk "  declara que nao verificou" "$(grep -q 'NAO VERIFICADO' "$TMP/err" && echo sim || echo nao)" "sim"
rc=$(gate true)
chk "  em continuacao forcada, avisa por additionalContext" \
    "$(jq -re '.hookSpecificOutput.additionalContext' "$TMP/out" >/dev/null 2>&1 && echo sim || echo nao)" "sim"
export CLAUDE_ADAPTERS_DIR="$SALVO"

cd /
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "regressao do gate verde" || echo "regressao do gate VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
