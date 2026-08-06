#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; W="$ROOT/install/apply-managed.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P=0;F=0; chk(){ if [ "$2" = "$3" ]; then P=$((P+1)); echo "PASS $1"; else F=$((F+1)); echo "FAIL $1 got=$2 want=$3"; fi; }
cat > "$T/fake.sh" <<'SH'
#!/usr/bin/env bash
p="${MANAGED_PREFIX}"; mkdir -p "$p/opt/evidence-gate" "$p/etc/claude-code"; echo new > "$p/opt/evidence-gate/x"; echo '{}' > "$p/etc/claude-code/managed-settings.json"
case "${FAKE_MODE:-ok}" in fail) exit 1;; unsafe) chmod 0777 "$p/opt/evidence-gate/x";; esac
SH
chmod +x "$T/fake.sh"
PFX="$T/p1"; FAKE_MODE=fail MANAGED_PREFIX="$PFX" EVIDENCE_GATE_MANAGED_LEGACY="$T/fake.sh" "$W" >/dev/null 2>&1; rc=$?
chk first-deploy-rc "$rc" 1; chk first-deploy-tree "$([ -e "$PFX/opt/evidence-gate" ]&&echo present||echo absent)" absent; chk first-deploy-policy "$([ -e "$PFX/etc/claude-code/managed-settings.json" ]&&echo present||echo absent)" absent
PFX="$T/p2"; mkdir -p "$PFX/opt/evidence-gate" "$PFX/etc/claude-code"; echo old > "$PFX/opt/evidence-gate/x"; echo old > "$PFX/etc/claude-code/managed-settings.json"
FAKE_MODE=fail MANAGED_PREFIX="$PFX" EVIDENCE_GATE_MANAGED_LEGACY="$T/fake.sh" "$W" >/dev/null 2>&1; rc=$?
chk existing-rc "$rc" 1; chk existing-tree "$(cat "$PFX/opt/evidence-gate/x")" old; chk existing-policy "$(cat "$PFX/etc/claude-code/managed-settings.json")" old
PFX="$T/p3"; FAKE_MODE=unsafe MANAGED_PREFIX="$PFX" EVIDENCE_GATE_MANAGED_LEGACY="$T/fake.sh" "$W" >/dev/null 2>&1; rc=$?
chk unsafe-rc "$rc" 1; chk unsafe-cleanup "$([ -e "$PFX/opt/evidence-gate" ]&&echo present||echo absent)" absent
echo "PASS=$P FAIL=$F"; [ "$F" -eq 0 ]
