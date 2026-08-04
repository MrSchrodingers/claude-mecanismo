#!/usr/bin/env python3
"""Validador do CLAIM LEDGER (evidence/claims/*.yaml).

POR QUE ESTE ARQUIVO EXISTE
---------------------------
Um ledger de alegacoes que apenas ARMAZENA texto e pior do que nao ter ledger: da a forma da
evidencia sem a substancia, que e precisamente o defeito que este repositorio persegue. O que
torna o ledger util nao e o formato - e ele ser FALSIFICAVEL.

Regra central, e a razao de o validador existir:

    toda referencia a evidencia e RESOLVIDA contra a suite real.
    Citar uma regressao ou um mutante que nao existe REPROVA.

O inventario de evidencia NAO e digitado aqui. E DERIVADO de tests/ a cada execucao. Uma lista
mantida a mao seria uma segunda copia da verdade, e duas copias divergem em silencio - foi
assim que este projeto comecou (README afirmando "28 assercoes" com a suite em 29).

CONTRATO DE EXTRACAO (o que conta como evidencia existente)
----------------------------------------------------------
  regressao : `echo "== <ID>. ..."` em tests/unit/*.sh
  mutante   : `mutante <ID> ...` no inicio da linha, OU `# <ID>: ...`, em tests/mutation/*.sh

Os dois espacos sao lidos de diretorios DISTINTOS de proposito: sem isso, um comentario
qualquer contendo "G12" num runner de mutacao passaria a valer como mutante, e a resolucao
deixaria de discriminar.

O QUE ESTE VALIDADOR NAO FAZ - limites declarados
------------------------------------------------
  - Nao verifica que a evidencia SUSTENTA a alegacao. Ele confere que a evidencia EXISTE, que
    o `warrant` foi escrito e que os limites foram declarados. A ligacao entre evidencia e
    tese e argumento humano, e nenhum schema a valida.
  - Nao detecta duplicacao de evidencia dentro do texto da alegacao.
  - Nao verifica o `ci_run`: seguir a URL exigiria rede numa fronteira de evidencia, e uma
    dependencia de rede que falha aberto seria pior que a ausencia da checagem.
"""
import os
import re
import subprocess
import sys

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

try:
    import yaml
except ImportError:
    # DEPENDENCIA DE ORACULO ausente, nao variacao de ambiente: sem parser nao ha como decidir
    # se o ledger e valido, e "nao reprovou" seria indistinguivel de "nao foi verificado".
    sys.stderr.write(
        "NAO VERIFICADO: pyyaml ausente. O ledger nao pode ser validado neste ambiente.\n"
        "Instale a versao pinada (ver .github/workflows/verify.yml).\n")
    sys.exit(EXIT_NAO_VERIFICADO)

TIPOS = {"empirical-invariant", "security-property", "runtime-observation", "method-rule"}
STATUS = {"supported-in-tested-domain", "refuted", "superseded", "not-verified"}
OBRIGATORIOS = ("claim_id", "claim", "type", "scope", "evidence", "warrant",
                "limitations", "status")
RE_CLAIM_ID = re.compile(r"^C-[0-9]{3}$")
# Espacos de nome disjuntos de proposito: `C-001` (alegacao) nunca colide com `C1` (caso de
# regressao da suite de concorrencia). Sem esta separacao a resolucao seria ambigua.
RE_EVID_ID = re.compile(r"^[A-Z]{1,3}[0-9]{1,3}[a-z]?$")


RE_CASO = re.compile(r"""^echo\s+['"]==\s+([A-Z]{1,3}[0-9]{1,3}[a-z]?)\.""")
RE_MUT = re.compile(r"^(?:mutante\s+|#\s*)([A-Z]{1,3}[0-9]{1,3})\b\s*[-: ]")


def _extrai(texto, rgx, strip):
    achados = set()
    for linha in texto.splitlines():
        m = rgx.match(linha.strip() if strip else linha)
        if m:
            achados.add(m.group(1))
    return achados


def inventario(raiz):
    """Inventario do WORKTREE. Nunca de lista digitada: uma lista mantida a mao seria uma
    segunda copia da verdade, e duas copias divergem em silencio."""
    regressoes, mutantes = set(), set()
    for sub, alvo, rgx, strip in (("unit", regressoes, RE_CASO, False),
                                  ("mutation", mutantes, RE_MUT, True)):
        d = os.path.join(raiz, "tests", sub)
        if not os.path.isdir(d):
            continue
        for nome in sorted(os.listdir(d)):
            if nome.endswith(".sh"):
                with open(os.path.join(d, nome), encoding="utf-8", errors="replace") as fh:
                    alvo |= _extrai(fh.read(), rgx, strip)
    return regressoes, mutantes


_CACHE_SNAP = {}


def inventario_no_commit(raiz, commit):
    """Inventario derivado do SNAPSHOT QUE A CLAIM DECLARA, e nao do worktree.

    POR QUE ISTO EXISTE (portao final, 2026-08-04). `scope.commit` era DECORATIVO: o validador
    conferia apenas que o objeto git existia, e resolvia a evidencia contra o worktree. Medido:
    as 16 claims declaravam `1319931`, e nesse snapshot os mutantes MC6/MC7 e os dois arquivos
    de observacao de C-015/C-016 NAO EXISTIAM. A frase impressa - "toda evidencia citada existe
    em tests/" - era verdadeira sobre o worktree e FALSA sobre o escopo que cada claim declara.
    Uma alegacao cujo lastro nao existe no snapshot que ela propria nomeia nao esta ancorada:
    esta datada errado, que e a forma silenciosa de nao estar ancorada.

    Devolve None quando o snapshot nao pode ser lido (git ausente): nao afirmar nem negar.
    """
    if commit in _CACHE_SNAP:
        return _CACHE_SNAP[commit]
    try:
        r = subprocess.run(["git", "-C", raiz, "ls-tree", "-r", "--name-only", commit,
                            "tests/unit/", "tests/mutation/"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            _CACHE_SNAP[commit] = None
            return None
        regressoes, mutantes = set(), set()
        for caminho in r.stdout.splitlines():
            if not caminho.endswith(".sh"):
                continue
            g = subprocess.run(["git", "-C", raiz, "show", f"{commit}:{caminho}"],
                               capture_output=True, text=True, timeout=30)
            if g.returncode != 0:
                continue
            if caminho.startswith("tests/unit/"):
                regressoes |= _extrai(g.stdout, RE_CASO, False)
            else:
                mutantes |= _extrai(g.stdout, RE_MUT, True)
        _CACHE_SNAP[commit] = (regressoes, mutantes)
        return _CACHE_SNAP[commit]
    except (OSError, subprocess.SubprocessError):
        _CACHE_SNAP[commit] = None
        return None


def existe_no_commit(raiz, commit, caminho):
    """O arquivo existe NAQUELE snapshot? None = indecidivel."""
    try:
        r = subprocess.run(["git", "-C", raiz, "cat-file", "-e", f"{commit}:{caminho}"],
                           capture_output=True, timeout=20)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return None


RE_SHA = re.compile(r"^[0-9a-fA-F]{7,40}$")


def commit_existe(raiz, sha):
    """Existe o commit? None = nao foi possivel decidir (git ausente).

    O valor vem de um ARQUIVO DO REPOSITORIO, que num cenario de repo hostil e entrada nao
    confiavel. Nao ha shell aqui (argv em lista), entao nao ha injecao de comando; o risco
    residual e de OPCAO: um valor comecando por '-' seria lido pelo git como flag, e nao como
    objeto. A validacao de forma ANTES da chamada fecha isso e nao depende de o git tratar
    '--' bem em `cat-file`, que nao trata.
    """
    if not RE_SHA.match(str(sha)):
        return False
    try:
        r = subprocess.run(["git", "-C", raiz, "cat-file", "-e", f"{sha}^{{commit}}"],
                           capture_output=True, timeout=20)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return None  # git indisponivel: nao afirmar nem negar


def valida(doc, arquivo, regressoes, mutantes, raiz, vistos):
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    if not isinstance(doc, dict):
        erro("o arquivo nao contem um mapeamento YAML no topo")
        return e

    for campo in OBRIGATORIOS:
        if campo not in doc or doc[campo] in (None, "", [], {}):
            erro(f"campo obrigatorio ausente ou vazio: '{campo}'")
    if e:
        return e

    cid = str(doc["claim_id"])
    if not RE_CLAIM_ID.match(cid):
        erro(f"claim_id '{cid}' fora do formato C-NNN")
    if cid in vistos:
        erro(f"claim_id '{cid}' duplicado (ja usado em {vistos[cid]})")
    else:
        vistos[cid] = os.path.basename(arquivo)
    esperado = f"{cid}.yaml"
    if os.path.basename(arquivo) != esperado:
        erro(f"nome do arquivo deveria ser '{esperado}' para casar com claim_id")

    if doc["type"] not in TIPOS:
        erro(f"type '{doc['type']}' fora do vocabulario {sorted(TIPOS)}")
    if doc["status"] not in STATUS:
        erro(f"status '{doc['status']}' fora do vocabulario {sorted(STATUS)}")

    escopo = doc.get("scope") or {}
    snap = None
    if not isinstance(escopo, dict) or not escopo.get("commit"):
        erro("scope.commit ausente - uma alegacao sem snapshot nao e verificavel")
    else:
        ok = commit_existe(raiz, str(escopo["commit"]))
        if ok is False:
            erro(f"scope.commit '{escopo['commit']}' nao existe neste repositorio")
        elif ok is True and RE_SHA.match(str(escopo["commit"])):
            # A EVIDENCIA E RESOLVIDA CONTRA O SNAPSHOT DECLARADO, nao contra o worktree.
            # `RE_SHA` ja validou a forma antes de qualquer chamada ao git.
            snap = inventario_no_commit(raiz, str(escopo["commit"]))
            if snap is None:
                erro("nao foi possivel ler o snapshot de scope.commit - "
                     "evidencia NAO VERIFICADA contra ele")
            else:
                regressoes, mutantes = snap
        elif ok is None:
            # ASSIMETRIA CORRIGIDA: `pyyaml` ausente ja saia 2 (NAO VERIFICADO), mas `git`
            # ausente devolvia None e o programa seguia imprimindo "ledger valido". Duas
            # dependencias de oraculo, dois tratamentos - e o silencioso era justamente o que
            # deixava TODO `scope.commit` sem resolucao enquanto o texto afirmava resolucao.
            erro("git indisponivel: scope.commit NAO VERIFICADO "
                 "(dependencia de oraculo ausente, nao aprovacao)")
    if not escopo.get("platforms"):
        erro("scope.platforms ausente - alegacao sem dominio testado nao tem alcance definido")

    ev = doc.get("evidence") or {}
    if not isinstance(ev, dict):
        erro("evidence deve ser um mapeamento")
        return e

    refs = 0
    for chave, universo, rotulo in (("regression", regressoes, "regressao"),
                                    ("mutants", mutantes, "mutante")):
        vals = ev.get(chave) or []
        if isinstance(vals, str):
            erro(f"evidence.{chave} deve ser lista, nao string")
            continue
        for v in vals:
            v = str(v)
            refs += 1
            if not RE_EVID_ID.match(v):
                erro(f"evidence.{chave}: '{v}' fora do formato de identificador")
            elif v not in universo:
                # A REGRA CENTRAL. Sem ela o ledger seria prosa com aparencia de rastro.
                erro(f"evidence.{chave} cita {rotulo} INEXISTENTE: '{v}' "
                     f"(nao encontrado em tests/)")

    obs = ev.get("observation")
    if obs is not None:
        if not isinstance(obs, dict) or not obs.get("recorded") or not obs.get("command"):
            erro("evidence.observation exige 'command' e 'recorded'")
        else:
            refs += 1
            rec = str(obs["recorded"])
            # CONFINAMENTO (auditoria de 2026-08-04). `os.path.join(raiz, x)` DESCARTA `raiz`
            # quando `x` e absoluto. Medido: uma claim cujo unico lastro era
            # `recorded: /etc/passwd` era aprovada, e o validador imprimia
            # "ledger valido: toda evidencia citada existe em tests/" - frase literalmente
            # falsa. O dano nao e a travessia: e a alegacao passar a ter lastro FORA do
            # repositorio enquanto o programa afirma que a evidencia foi resolvida.
            if os.path.isabs(rec) or ".." in rec.split("/"):
                erro(f"evidence.observation.recorded precisa ser caminho relativo dentro do "
                     f"repositorio, sem '..': '{rec}'")
            else:
                alvo = os.path.realpath(os.path.join(raiz, rec))
                base = os.path.realpath(raiz)
                if not (alvo == base or alvo.startswith(base + os.sep)):
                    erro(f"evidence.observation.recorded escapa do repositorio: '{rec}'")
                elif not os.path.isfile(alvo):
                    erro(f"evidence.observation.recorded aponta para arquivo inexistente: "
                         f"'{rec}'")
                elif snap is not None and isinstance(escopo, dict) and escopo.get("commit"):
                    # Existir no worktree NAO basta: a claim declara um snapshot, e o lastro
                    # tem de existir NELE. Medido: C-015 e C-016 citavam observacoes que nao
                    # existiam no commit que declaravam.
                    v = existe_no_commit(raiz, str(escopo["commit"]), rec)
                    if v is False:
                        erro(f"evidence.observation.recorded existe no worktree mas NAO no "
                             f"snapshot declarado ({escopo['commit']}): '{rec}'")

    if refs == 0:
        erro("nenhuma referencia de evidencia (regression, mutants ou observation). "
             "Uma alegacao sem lastro nao entra no ledger.")

    if not isinstance(doc.get("limitations"), list) or not doc["limitations"]:
        erro("limitations deve ser uma lista nao vazia - toda alegacao tem alcance finito")

    ce = doc.get("counterexamples")
    if ce is not None:
        if not isinstance(ce, list):
            erro("counterexamples deve ser lista")
        else:
            for i, c in enumerate(ce):
                if not isinstance(c, dict) or not c.get("commit") or not c.get("result"):
                    erro(f"counterexamples[{i}] exige 'commit' e 'result'")
    return e


def main(argv):
    raiz = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.abspath(
        os.path.join(os.path.dirname(__file__), ".."))
    cdir = argv[2] if len(argv) > 2 else os.path.join(raiz, "evidence", "claims")

    regressoes, mutantes = inventario(raiz)
    # AUTOCHECAGEM: inventario vazio significa que a extracao quebrou. Sem isto o validador
    # reprovaria TUDO (falso vermelho) ou, se a regex passasse a casar demais, aprovaria tudo
    # (falso verde). Em ambos os casos ele deixaria de medir o que diz medir.
    if not regressoes or not mutantes:
        sys.stderr.write(
            f"NAO VERIFICADO: extracao de inventario vazia "
            f"(regressoes={len(regressoes)}, mutantes={len(mutantes)}). "
            f"O contrato de extracao nao casa com tests/ - corrija antes de confiar no ledger.\n")
        return EXIT_NAO_VERIFICADO

    if not os.path.isdir(cdir):
        sys.stderr.write(f"NAO VERIFICADO: diretorio de claims inexistente: {cdir}\n")
        return EXIT_NAO_VERIFICADO

    arquivos = sorted(f for f in os.listdir(cdir) if f.endswith((".yaml", ".yml")))
    if not arquivos:
        sys.stderr.write(f"NAO VERIFICADO: nenhuma claim em {cdir}\n")
        return EXIT_NAO_VERIFICADO

    erros, vistos = [], {}
    for nome in arquivos:
        caminho = os.path.join(cdir, nome)
        try:
            with open(caminho, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            erros.append(f"{nome}: YAML invalido: {exc}")
            continue
        erros.extend(valida(doc, caminho, regressoes, mutantes, raiz, vistos))

    print(f"inventario do worktree: {len(regressoes)} regressoes, {len(mutantes)} mutantes "
          f"(cada claim e resolvida contra o SEU scope.commit, nao contra este)")
    print(f"claims lidas: {len(arquivos)}")
    if erros:
        print(f"\nVIOLACOES ({len(erros)}):")
        for x in erros:
            print(f"  - {x}")
        return EXIT_VIOLACAO
    print("ledger valido: toda evidencia citada existe no SNAPSHOT que cada claim declara")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
