#!/usr/bin/env bash
set -uo pipefail
LEGACY="${EVIDENCE_GATE_MANAGED_LEGACY:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/apply-managed-legacy.sh}"
[ -x "$LEGACY" ] || { echo "NOT_VERIFIED: instalador legado ausente" >&2; exit 2; }
case "${1:-}" in --verify|--revert) exec "$LEGACY" "$@" ;; esac
PREFIX="${MANAGED_PREFIX:-}"; OPT="${PREFIX}/opt/evidence-gate"; SETTINGS="${PREFIX}/etc/claude-code/managed-settings.json"
REC="$(mktemp -d "${TMPDIR:-/tmp}/evidence-gate-recovery.XXXXXX")" || exit 1
cleanup(){ rm -rf "$REC" 2>/dev/null || true; }; trap cleanup EXIT
HAD_OPT=0; HAD_SETTINGS=0
if [ -d "$OPT" ]; then HAD_OPT=1; cp -a "$OPT" "$REC/opt" || exit 1; fi
if [ -f "$SETTINGS" ]; then HAD_SETTINGS=1; cp -a "$SETTINGS" "$REC/settings.json" || exit 1; fi
rollback(){ local bad=0; rm -rf "$OPT" 2>/dev/null || bad=1; rm -f "$SETTINGS" 2>/dev/null || bad=1; if [ "$HAD_OPT" -eq 1 ]; then mkdir -p "$(dirname "$OPT")" && cp -a "$REC/opt" "$OPT" || bad=1; fi; if [ "$HAD_SETTINGS" -eq 1 ]; then mkdir -p "$(dirname "$SETTINGS")" && cp -a "$REC/settings.json" "$SETTINGS" || bad=1; fi; if [ "$bad" -ne 0 ]; then trap - EXIT; echo "ROLLBACK_FAILED: recuperação preservada em $REC" >&2; return 1; fi; return 0; }
"$LEGACY" "$@"; rc=$?
if [ "$rc" -ne 0 ]; then rollback && exit "$rc" || exit 70; fi
unsafe="$(find "$OPT" -xdev \( -type f -o -type d \) -perm /022 -print -quit 2>/dev/null || true)"
if [ -n "$unsafe" ]; then echo "permissão insegura: $unsafe" >&2; rollback && exit 1 || exit 70; fi
if [ -z "$PREFIX" ] && [ "$(id -u)" -eq 0 ]; then bad="$(find "$OPT" -xdev \! -user root -o \! -group root -print -quit 2>/dev/null || true)"; if [ -n "$bad" ]; then echo "posse insegura: $bad" >&2; rollback && exit 1 || exit 70; fi; fi
cleanup; trap - EXIT; echo "managed transaction committed"
