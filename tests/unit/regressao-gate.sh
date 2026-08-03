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
REPO_ROOT="$PWD"          # os casos fazem cd; guarde a raiz antes
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

echo "== G6. dependencia ESTRUTURAL ausente e lacuna, nao sucesso silencioso =="
# Ferramenta de adaptador ausente ja virava lacuna; a do proprio gate saia 0 calada.
novo_repo g6
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
BIN="$TMP/bin-sem-jq"; mkdir -p "$BIN"
for b in cat git sha256sum grep sed sort awk cut date mkdir timeout readlink ruff bash; do
  p="$(command -v $b 2>/dev/null)" && ln -sf "$p" "$BIN/$b"
done
rc=$(PATH="$BIN" printf '{"stop_hook_active":false}' | PATH="$BIN" bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?)
chk "sem jq em repo git: BARRA em vez de sair 0" "$rc" 2
chk "  nomeia a dependencia ausente" "$(grep -q "jq" "$TMP/err" && echo sim || echo nao)" "sim"
rc=$(PATH="$BIN" printf '{"stop_hook_active":true}' | PATH="$BIN" bash "$GATE" >/dev/null 2>&1; echo $?)
chk "  em continuacao forcada, nao trava a sessao" "$rc" 0

echo "== G7. adaptador que EXECUTA codigo do repo nao roda em auto-deteccao =="
# A doc da Microsoft adverte que `dotnet format` compila e roda analisadores do projeto.
novo_repo g7
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > App.csproj
printf 'class P { static void Main() {} }\n' > Program.cs; git add -A
rc=$(gate false)
chk "repo .NET nao passa em silencio" "$rc" 2
chk "  declara LACUNA (nao falha de codigo)" "$(grep -q 'LACUNA DE COBERTURA' "$TMP/err" && echo sim || echo nao)" "sim"
chk "  nomeia o ecossistema" "$(grep -q 'dotnet' "$TMP/err" && echo sim || echo nao)" "sim"
# Sem esta assercao o caso passa mesmo com a garantia removida: o adaptador entraria na
# execucao e a lacuna viria de 'dotnet nao esta no PATH', que e outro motivo. Achado por M7.
chk "  o motivo e EXECUTAR codigo do repo, nao binario ausente" \
    "$(grep -q 'declara executar codigo do repositorio' "$TMP/err" && echo sim || echo nao)" "sim"

echo "== G8. identidade do AMBIENTE cobre o binario, nao so o caminho =="
# Cache `pass` nao pode sobreviver a troca do verificador no mesmo path.
novo_repo g8
FAKEBIN="$TMP/fake"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\n[ "$1" = "--version" ] && { echo "fakelint 1.0"; exit 0; }\nexit 0\n' > "$FAKEBIN/fakelint"
chmod +x "$FAKEBIN/fakelint"
ADT="$TMP/adap"; mkdir -p "$ADT"
jq -n '{id:"fake",ecosystem:"fake",operation_class:"parse",extensions:[".fk"],
        exec:{command:"fakelint",args:["check"]},
        declared_effects:{executes_repository_code:false,writes_repository:false,network:false},
        rationale:"fixture", limits:{timeout_seconds:10}}' > "$ADT/fake.json"
echo "conteudo" > alvo.fk
rm -f "$HOME/.claude/evidence"/*.jsonl   # isola o ledger deste caso
SALVO2="$CLAUDE_ADAPTERS_DIR"; export CLAUDE_ADAPTERS_DIR="$ADT"; export PATH="$FAKEBIN:$PATH"
rc=$(gate false); chk "primeira execucao aprova" "$rc" 0
LED="$HOME/.claude/evidence"; ENV1=$(cat "$LED"/*.jsonl 2>/dev/null | tail -1 | jq -r '.env')
# mesmo caminho, binario DIFERENTE (versao nova)
printf '#!/bin/sh\n[ "$1" = "--version" ] && { echo "fakelint 2.0"; exit 0; }\nexit 1\n' > "$FAKEBIN/fakelint"
chmod +x "$FAKEBIN/fakelint"
rc=$(gate false)
ENV2=$(cat "$LED"/*.jsonl 2>/dev/null | tail -1 | jq -r '.env')
chk "trocar o binario no MESMO path invalida o cache" "$([ "$ENV1" != "$ENV2" ] && echo sim || echo nao)" "sim"
chk "  e o veredito novo reprova" "$rc" 2
export CLAUDE_ADAPTERS_DIR="$SALVO2"

echo "== G9. dependencia estrutural: 'git' ausente com .git presente =="
# G6 cobria so `jq`. Sem este caso, `command -v git || exit 0` seguia fail-open silencioso.
novo_repo g9
printf 'def f():\n    return indefinido\n' > quebrado.py; git add -A
BIN2="$TMP/bin-sem-git"; mkdir -p "$BIN2"
for b in cat jq sha256sum grep sed sort awk cut date mkdir timeout readlink ruff bash dirname; do
  p="$(command -v $b 2>/dev/null)" && ln -sf "$p" "$BIN2/$b"
done
rc=$(printf '{"stop_hook_active":false}' | PATH="$BIN2" bash "$GATE" >"$TMP/out" 2>"$TMP/err"; echo $?)
chk "sem git, com .git presente: BARRA" "$rc" 2
chk "  nomeia a dependencia ausente" "$(grep -q "'git' nao esta no PATH" "$TMP/err" && echo sim || echo nao)" "sim"
FORA="$TMP/nao-e-repo"; mkdir -p "$FORA"; cd "$FORA"
rc=$(printf '{"stop_hook_active":false}' | PATH="$BIN2" bash "$GATE" >/dev/null 2>&1; echo $?)
chk "  fora de repositorio, inerte segue legitimo" "$rc" 0

echo "== G10. --dry-run do instalador NAO altera estado (byte a byte) =="
# Regressao MEDIDA: a etapa de convergencia rodava `rm -rf` antes de checar DRY, e o modo
# anunciado como inspecao segura apagou um componente.
DH="$TMP/dryhome/.claude"; mkdir -p "$DH"
( cd "$REPO_ROOT" && CLAUDE_HOME="$DH" bash install/apply.sh >/dev/null 2>&1 )
echo "orfao" > "$DH/hooks/saiu.sh"
printf 'hooks/saiu.sh\n' >> "$DH/evidence-gate/managed-files.lock"
dig(){ find "$1" -type f ! -path '*/backups/*' -exec sha256sum {} + 2>/dev/null | sed "s|$1||" | sort -k2 | sha256sum | cut -c1-32; }
rm -rf "$DH/backups"      # o backup existente veio do apply que preparou o cenario
ANTES=$(dig "$DH")
( cd /home/ti/evidence-gate && CLAUDE_HOME="$DH" bash install/apply.sh --dry-run >"$TMP/dry" 2>&1 )
DEPOIS=$(dig "$DH")
chk "estado identico apos --dry-run" "$([ "$ANTES" = "$DEPOIS" ] && echo sim || echo nao)" "sim"
chk "  o orfao continua no disco" "$([ -f "$DH/hooks/saiu.sh" ] && echo sim || echo nao)" "sim"
chk "  mas o plano ANUNCIA a remocao" "$(grep -q 'REMOVERIA' "$TMP/dry" && echo sim || echo nao)" "sim"
chk "  e nao cria backup" "$([ -d "$DH/backups" ] && echo nao || echo sim)" "sim"

cd /
echo
echo "================ PASS=$P  FAIL=$F ================"
# CONTAGEM E INVARIANTE, nao descricao. Sem isto, apagar cinco casos deixa PASS=15/FAIL=0 e a
# suite segue verde - o numero no relatorio viraria documentacao, nao garantia.
EXPECTED=28
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "regressao do gate verde ($P/$EXPECTED)" || echo "regressao do gate VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
