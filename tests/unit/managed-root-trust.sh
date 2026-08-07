#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
W="$PWD/install/apply-managed.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"; if command -v sudo >/dev/null 2>&1; then sudo rm -rf "$T.root" 2>/dev/null || true; fi' EXIT
P=0; F=0
pass(){ P=$((P+1)); echo "PASS $1"; }
fail(){ F=$((F+1)); echo "FAIL $1"; }

if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true >/dev/null 2>&1; then
  echo "SKIP managed-root-trust: sudo nao-interativo indisponivel"
  exit 0
fi

# 1. The stock repository on a hosted runner is user-owned. Running the stock wrapper as root
# must fail before any sibling helper can execute.
MARK="$T/should-not-exist"
mkdir -p "$T/fake-repo/install"
cp "$W" "$T/fake-repo/install/apply-managed.sh"
cat > "$T/fake-repo/install/apply-managed-legacy.sh" <<SH
#!/usr/bin/env bash
touch '$MARK'
exit 0
SH
chmod +x "$T/fake-repo/install/"*.sh
sudo -n env -u MANAGED_PREFIX -u EVIDENCE_GATE_MANAGED_LEGACY \
  "$T/fake-repo/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ] && [ ! -e "$MARK" ]; then pass user-owned-source-rejected; else fail user-owned-source-rejected; fi

# 2. A root-owned, non-writable, symlink-free snapshot is accepted. The fake delegated installer
# does no writes because this case only exercises the source-of-code trust precondition.
ROOT_COPY="$T.root/repo"
sudo mkdir -p "$ROOT_COPY/install"
sudo cp "$W" "$ROOT_COPY/install/apply-managed.sh"
sudo sh -c "cat > '$ROOT_COPY/install/apply-managed-legacy.sh' <<'SH'
#!/usr/bin/env bash
exit 0
SH"
sudo chown -R root:root "$T.root"
sudo chmod 0755 "$T.root" "$ROOT_COPY" "$ROOT_COPY/install" "$ROOT_COPY/install/"*.sh
sudo -n env -u MANAGED_PREFIX -u EVIDENCE_GATE_MANAGED_LEGACY \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass root-owned-source-accepted; else fail root-owned-source-accepted; fi

# 3. The privileged override is forbidden on the real root even if its target is itself root-owned.
sudo -n env -u MANAGED_PREFIX EVIDENCE_GATE_MANAGED_LEGACY="$ROOT_COPY/install/apply-managed-legacy.sh" \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ]; then pass privileged-override-rejected; else fail privileged-override-rejected; fi

# 4. Any symlink inside the privileged source closure invalidates the snapshot.
sudo ln -s /etc/passwd "$ROOT_COPY/forbidden-link"
sudo -n env -u MANAGED_PREFIX -u EVIDENCE_GATE_MANAGED_LEGACY \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ]; then pass source-symlink-rejected; else fail source-symlink-rejected; fi
sudo rm -f "$ROOT_COPY/forbidden-link"

# 5. Group/world-writable source material invalidates the privileged snapshot.
sudo chmod 0775 "$ROOT_COPY/install"
sudo -n env -u MANAGED_PREFIX -u EVIDENCE_GATE_MANAGED_LEGACY \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ]; then pass writable-source-rejected; else fail writable-source-rejected; fi

echo "PASS=$P FAIL=$F"
[ "$F" -eq 0 ]
