#!/usr/bin/env bash
# Suite de regressao. Cada caso existe porque um defeito REAL passou por ele.
#
# ISOLAMENTO - o que e isolado e o que nao e, e por que:
#  - ISOLADO: caminhos de consentimento (sentinela, lista de aprovacao) via HOME proprio, e o
#    stamp de throttle por repo. Sem isso, estado do usuario faz o teste passar/falhar por
#    coincidencia - aconteceu.
#  - NAO ISOLADO de proposito: a toolchain. Rodar com $HOME fabricado faz ferramenta em
#    ~/.local deixar de resolver, e o teste falharia por AUSENCIA de ferramenta, nao por
#    defeito - falso negativo.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
C0="$PWD/camada0-universal/hooks"
C1="$PWD/camada1-toolchain/hooks"
AD="$PWD/camada1-toolchain/adapters"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
run(){ printf '%s' "$1" | bash "$2" 2>"${3:-/dev/null}"; echo $?; }
limpa(){ local k; k="$(printf '%s' "$1" | md5sum | cut -c1-12)"; rm -f "$HOME/.claude/logs/.verifygate-$k" 2>/dev/null; }
SENT=".$(printf 'fa%s' 'ble')-allowed"; MODEL_X="$(printf 'fa%s' 'ble')"

echo "== 1. sintaxe e JSON =="
bad=0; for f in "$C0"/*.sh "$C1"/*.sh; do bash -n "$f" 2>/dev/null || { echo "    QUEBRADO: $f"; bad=1; }; done
chk "bash -n em $(ls "$C0"/*.sh "$C1"/*.sh | wc -l) hooks" "$bad" 0
bad=0; for a in "$AD"/*.json; do jq -e . "$a" >/dev/null 2>&1 || { echo "    invalido: $a"; bad=1; }; done
chk "adaptadores sao JSON valido" "$bad" 0

echo "== 2. CONTRATO DO ADAPTADOR: analyzer exige justificativa de nao-execucao =="
# A distincao analyzer/test e a correcao de uma vulnerabilidade (classe CVE-2025-59536).
# Sem a justificativa escrita, ninguem revisa se o comando realmente nao executa codigo do repo.
bad=0
for a in "$AD"/*.json; do
  jq -e '.analyzer.cmd' "$a" >/dev/null 2>&1 || continue
  j="$(jq -r '.analyzer.porque_nao_executa // empty' "$a")"
  [ -n "$j" ] || { echo "    sem porque_nao_executa: $(basename "$a")"; bad=1; }
done
chk "todo analyzer justifica por que nao executa codigo do repo" "$bad" 0
bad=0
for a in "$AD"/*.json; do
  jq -e '.test.cmd' "$a" >/dev/null 2>&1 || continue
  [ "$(jq -r '.test.executa_codigo_do_repo // false' "$a")" = "true" ] || { echo "    test sem flag: $(basename "$a")"; bad=1; }
done
chk "todo test declara que executa codigo do repo" "$bad" 0

echo "== 3. AMPLITUDE: o gate reconhece ecossistema sem editar o hook =="
# Era o defeito estrutural do global anterior: 19 mencoes de python/npm dentro do hook.
for eco in python node go rust dotnet java; do
  [ -f "$AD/$eco.json" ] && chk "adaptador presente: $eco" 0 0
done
D="$TMP/cs"; mkdir -p "$D"; ( cd "$D"; git init -q .; git config user.email t@t; git config user.name t
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > App.csproj
  printf 'class P { static void Main() {} }\n' > Program.cs
  git add -A; git commit -qm b ) >/dev/null 2>&1
printf '// e\n' >> "$D/Program.cs"; limpa "$D"
OUT="$( cd "$D" && printf '{}' | bash "$C1/verify-gate.sh" 2>&1 )"
printf '%s' "$OUT" | grep -q "dotnet"; chk "repo C# e reconhecido (era INERTE no global anterior)" $? 0

echo "== 4. FERRAMENTA AUSENTE != FALHA DE CODIGO =="
# Barrar por falta de ferramenta e o falso positivo que faz o usuario desligar o gate.
printf '%s' "$OUT" | grep -q "LACUNA DE COBERTURA"; chk "ferramenta ausente vira LACUNA, nao falha" $? 0
printf '%s' "$OUT" | grep -q "NAO VERIFICADO"; chk "  declara o estado como nao verificado" $? 0

echo "== 5. SEGURANCA: comando do REPO nao executa sem aprovacao de root =="
# Classe CVE-2025-59536. PoC: repo hostil grava marcador.
R3="$TMP/hostil"; mkdir -p "$R3/.claude"; MARK="$TMP/PWNED"
( cd "$R3"; git init -q .; git config user.email t@t; git config user.name t
  printf 'def f():\n    return 1\n' > app.py
  printf 'printf pwned > %s\n' "$MARK" > .claude/verify-cmd
  git add -A; git commit -qm b ) >/dev/null 2>&1
printf '# e\n' >> "$R3/app.py"; limpa "$R3"
( cd "$R3" && printf '{}' | bash "$C1/verify-gate.sh" >/dev/null 2>&1 )
[ ! -f "$MARK" ]; chk "verify-cmd de repo hostil NAO executa" $? 0
HI="$TMP/hi"; mkdir -p "$HI/.claude/logs"
CH=$(printf 'printf pwned > %s' "$MARK" | sha256sum | cut -c1-16)
printf '%s\n' "$CH" > "$HI/.claude/verify-cmd-approved"    # criada pelo usuario-agente
limpa "$R3"; rm -f "$HI"/.claude/logs/.verifygate-*
( cd "$R3" && HOME="$HI" CLAUDE_ADAPTERS_DIR="$AD" bash -c "printf '{}' | bash '$C1/verify-gate.sh'" >/dev/null 2>&1 )
[ ! -f "$MARK" ]; chk "lista de aprovacao NAO-root e ignorada" $? 0
# MUTACAO: prova que o teste acima testa a POSSE, e nao um hash desalinhado
MUT="$TMP/mutante.sh"
python3 - "$C1/verify-gate.sh" "$MUT" <<'PYEOF'
import sys, re
s = open(sys.argv[1]).read()
s = re.sub(r'OWNER="\$\(stat[^\n]*\)"', 'OWNER="root"', s)
open(sys.argv[2], 'w').write(s)
PYEOF
grep -q 'OWNER="root"' "$MUT"; chk "mutante construido (checagem de posse removida)" $? 0
rm -f "$MARK"; limpa "$R3"; rm -f "$HI"/.claude/logs/.verifygate-*
# CLAUDE_ADAPTERS_DIR e obrigatorio: o mutante vive em /tmp e perde o caminho relativo.
( cd "$R3" && HOME="$HI" CLAUDE_ADAPTERS_DIR="$AD" bash -c "printf '{}' | bash '$MUT'" >/dev/null 2>&1 )
[ -f "$MARK" ]; chk "MUTANTE executa -> o teste acima testa mesmo a garantia" $? 0
rm -f "$MARK"

VAZIO="$TMP/sem-tabela"; mkdir -p "$VAZIO"
R=$( cd "$R3" && CLAUDE_ADAPTERS_DIR="$VAZIO" printf '{}' | CLAUDE_ADAPTERS_DIR="$VAZIO" bash "$C1/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "tabela ausente NAO e inercia silenciosa (declara o gate desligado)" "$R" 2

echo "== 6. ANALISADOR roda; suite do projeto NAO roda sozinha =="
R1="$TMP/py"; mkdir -p "$R1/tests"; ( cd "$R1"; git init -q .; git config user.email t@t; git config user.name t
  printf 'def f():\n    return 1\n' > app.py
  printf 'import pathlib\npathlib.Path("%s").write_text("x")\n' "$TMP/PWN_CONFTEST" > tests/conftest.py
  git add -A; git commit -qm b ) >/dev/null 2>&1
printf 'def g():\n    return nao_existe\n' >> "$R1/app.py"; limpa "$R1"
R=$( cd "$R1" && printf '{}' | bash "$C1/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "analyzer BARRA com erro de lint (F821)" "$R" 2
[ ! -f "$TMP/PWN_CONFTEST" ]; chk "  conftest.py do repo NAO foi executado" $? 0
printf 'def f():\n    return 1\n' > "$R1/app.py"; limpa "$R1"
R=$( cd "$R1" && printf '{}' | bash "$C1/verify-gate.sh" >/dev/null 2>&1; echo $? )
chk "analyzer LIBERA com codigo limpo" "$R" 0

echo "== 7. CANAL: todo hook usa canal que o runtime ENTREGA =="
# stderr com exit 0 nao chega ao modelo: dois hooks foram decoracao por versoes inteiras.
python3 - "$C0" "$C1" <<'PYEOF'
import pathlib, sys
UPS = {'lentes.sh', 'graphify-scout-mode.sh'}
SO_LOG = {'subagent-probe.sh'}
ruins = []
for d in sys.argv[1:]:
    for f in sorted(pathlib.Path(d).glob('*.sh')):
        s = f.read_text()
        ok = ('exit 2' in s) or ('additionalContext' in s) or ('updatedToolOutput' in s) \
             or (f.name in UPS) or (f.name in SO_LOG)
        if not ok: ruins.append(f.name)
if ruins: print("NAO ENTREGAM:", " ".join(ruins)); raise SystemExit(1)
raise SystemExit(0)
PYEOF
chk "nenhum hook usa apenas stderr+exit 0" $? 0

echo "== 8. camada 0: garantias agnosticas de stack =="
G="$C0/fable-guard.sh"; HL="$TMP/hl"; mkdir -p "$HL/.claude"
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "nega modelo restrito sem sentinela" "$R" 2
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"agent_id\":\"s1\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "nega em SUBAGENTE (sem excecao)" "$R" 2
echo $(( $(date +%s) + 3600 )) > "$HL/.claude/$SENT"
R=$(HOME="$HL" bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"model\":\"$MODEL_X\"}}' | bash '$G'" 2>/dev/null; echo $?)
chk "NEGA sentinela nao pertencente a root" "$R" 2
S="$C0/subagent-contract.sh"
OK='RESULTADO: ok
EVIDENCIA: a.py:1; pytest -> exit 0'
R=$(run "$(jq -nc --arg m "$OK" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "contrato aceita retorno com ancora" "$R" 0
ACC='RESULTADO: ok
EVIDÊNCIA: a.py:1; pytest -> exit 0'
R=$(run "$(jq -nc --arg m "$ACC" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  aceita EVIDENCIA acentuada (PT-BR reprovava 25%)" "$R" 0
R=$(run "$(jq -nc --arg m "tudo certo, pode seguir" '{hook_event_name:"SubagentStop",agent_type:"refutador",last_assistant_message:$m}')" "$S")
chk "  barra retorno sem evidencia" "$R" 2
O="$C0/output-budget.sh"
# acima do limite de 12.000 B, senao o hook sai 0 sem emitir e o teste reprova um hook correto
BIG=$(python3 -c "print('\n'.join(f'linha de saida numero {i} com texto suficiente' for i in range(500)))")
RO=$(jq -nc --arg s "$BIG" '{tool_name:"Bash",tool_response:{stdout:$s,stderr:"",interrupted:false}}' | bash "$O")
printf '%s' "$RO" | jq -e '.hookSpecificOutput.updatedToolOutput | type == "object"' >/dev/null 2>&1
chk "output-budget emite OBJETO (string era rejeitada pelo runtime)" $? 0

echo "== 9. ciclo de vida de skill: criar E depreciar =="
SK="$PWD/camada0-universal/skills"
for k in forge depreciar; do
  [ -f "$SK/$k/SKILL.md" ]; chk "skill $k presente" $? 0
  head -1 "$SK/$k/SKILL.md" | grep -q '^---$'; chk "  $k tem frontmatter" $? 0
  grep -q '^description:' "$SK/$k/SKILL.md"; chk "  $k tem description (o gatilho)" $? 0
done
# o ciclo so fecha se um aponta para o outro
grep -q 'depreciar' "$SK/forge/SKILL.md"; chk "forge aponta para o depreciador (ciclo fechado)" $? 0
grep -q 'forge' "$SK/depreciar/SKILL.md"; chk "depreciar aponta para o criador" $? 0
# a armadilha dos dois canais precisa estar documentada, senao a medicao repete o erro
grep -q 'tool_use' "$SK/depreciar/SKILL.md" && grep -q '/nome\|/cmd\|canal' "$SK/depreciar/SKILL.md"
chk "depreciar documenta os DOIS canais de invocacao" $? 0
grep -qE 'ressalva|\(a\)|\(b\)|\(c\)' "$SK/depreciar/SKILL.md"; chk "  documenta as ressalvas antes de arquivar" $? 0
bash -n scripts/medir-skills.sh; chk "medir-skills.sh sintaxe" $? 0

echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "suite verde" || echo "suite VERMELHA"
exit "$F"
