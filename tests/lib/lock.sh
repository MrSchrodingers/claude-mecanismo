#!/usr/bin/env bash
# LOCK DE EXECUCAO DAS SUITES. Este arquivo e SOURCED, nunca executado direto.
#
# POR QUE EXISTE - reproduzido em 2026-08-04, nao inferido:
#   bash tests/mutation/contrato.sh &   # muta subagent-contract.sh NO LUGAR
#   sleep 6; bash tests/unit/run.sh     # le o mesmo arquivo
#   -> run.sh: "FAIL  BARRA blocos completos SEM ancora (got=0 want=2)", exit 1
#   -> isolada, no mesmo instante seguinte: PASS=45 FAIL=0, exit 0
#
# O perigo nao e a suite ficar vermelha: e a vermelhidao ser PLAUSIVEL. O caso acusado parece
# um defeito real no discriminador da ancora, e o operador iria depurar um bug que nao existe.
# A corrida simetrica tambem cabe: uma suite lendo o hook MUTADO (mais permissivo) durante a
# janela de mutacao pode mascarar defeito real - falso verde com a mesma causa.
#
# ESCOPO DA GARANTIA: isto protege contra corrida entre suites DESTE repositorio. Nao protege
# contra edicao manual concorrente nem contra outro clone apontando para o mesmo ~/.claude.
#
# DUAS DECISOES DE DESENHO, ambas deliberadas:
#
# 1. FALHA RAPIDO (`flock -n`), nao espera. Esperar serializaria e as duas execucoes passariam
#    - conveniente, e exatamente o tipo de absorcao silenciosa que este repositorio existe para
#    nao fazer. Exit 3 e codigo distinto de 0 (verde), 1 (vermelho) e 2 (bloqueio de hook):
#    "houve corrida" nunca se confunde com "ha defeito".
#
# 2. RE-ENTRANTE POR VARIAVEL EXPORTADA. Os runners de mutacao INVOCAM as suites de regressao.
#    Com lock nao reentrante o filho travaria no lock do pai - deadlock por desenho, e o
#    proprio mecanismo de protecao viraria o defeito. A marca no ambiente diz que a arvore ja
#    esta protegida por um ancestral.
#
# ARMADILHA JA PAGA (handoff, item 8): `$TMPDIR` pode estar VAZIO, nao apenas indefinido, no
# zsh - ai "$TMPDIR/x" vira "/x" e falha com permission denied. `${TMPDIR:-/tmp}` cobre os dois
# casos; `${TMPDIR-/tmp}` cobriria so o indefinido e reintroduziria o bug.

if [ "${EVIDENCE_GATE_LOCK:-}" != "held" ]; then
  if ! command -v flock >/dev/null 2>&1; then
    # LACUNA DECLARADA, nao inercia silenciosa: sem flock nao ha exclusao mutua. Seguir e
    # correto (voltar ao comportamento anterior nao e regressao); calar nao seria.
    echo "AVISO: flock ausente - as suites rodam SEM protecao contra corrida (lacuna declarada)." >&2
  else
    _lk_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    # ONDE FICA O LOCK - importa mais do que parece. Ancorar em $TMPDIR abre um furo: dois
    # processos do MESMO repositorio com $TMPDIR diferente calculariam arquivos diferentes e
    # NAO se excluiriam - exclusao mutua que depende de variavel de ambiente nao e exclusao
    # mutua. Por isso a preferencia e `.git/`, que e o mesmo caminho para todo processo que
    # enxerga este repositorio, e e gravavel sempre que a arvore e.
    #   EVIDENCE_GATE_LOCK_FILE: override explicito. Existe para tests/unit/concorrencia.sh,
    #   que precisa exercitar o lock sem colidir com o lock real tomado por scripts/status.sh.
    #   Nao usar em producao - apontar dois processos para arquivos distintos e desligar a
    #   garantia, nao configura-la.
    if [ -n "${EVIDENCE_GATE_LOCK_FILE:-}" ]; then
      _lk_file="$EVIDENCE_GATE_LOCK_FILE"
    elif [ -d "$_lk_root/.git" ] && [ -w "$_lk_root/.git" ]; then
      _lk_file="$_lk_root/.git/evidence-gate-suite.lock"
    else
      # Sem `.git` gravavel (export por tarball, worktree somente-leitura): cai para o
      # temporario. LIMITE DECLARADO: aqui a exclusao volta a depender de $TMPDIR coincidir.
      _lk_file="${TMPDIR:-/tmp}/evidence-gate-$(printf '%s' "$_lk_root" | sha256sum | cut -c1-16).lock"
    fi
    if ! exec 9>"$_lk_file"; then
      echo "AVISO: nao foi possivel abrir o lock em '$_lk_file' - seguindo sem protecao." >&2
    elif ! flock -n 9; then
      {
        echo "LOCK: ja ha uma suite deste repositorio em execucao."
        echo "  arquivo de lock: $_lk_file"
        echo "As suites NAO sao reentrantes entre si: os runners de mutacao editam arquivos do"
        echo "repositorio NO LUGAR, e outra suite lendo nesse instante reporta FAIL plausivel e"
        echo "falso - ou, pior, verde falso. Rode uma por vez; se algo ficou em background,"
        echo "espere terminar."
        echo "exit 3 = corrida detectada. NAO e defeito de codigo e NAO e resultado de teste."
      } >&2
      exit 3
    else
      export EVIDENCE_GATE_LOCK=held
    fi
  fi
fi
