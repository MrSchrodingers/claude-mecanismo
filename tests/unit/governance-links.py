#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
registry = json.loads((ROOT / "orchestration/registry.json").read_text(encoding="utf-8"))

expected = {
    "policy": "orchestration/skill-policy.json",
    "evaluation_protocol": "orchestration/evaluation-protocol.json",
    "method": "docs/method/skill-evaluation-protocol.md",
    "adr": "docs/adr/0025-skills-evidence-gated.md",
}
actual = registry.get("skill_governance")

if actual != expected:
    raise SystemExit(f"FAIL skill_governance divergente: {actual!r}")

for label, raw_path in expected.items():
    path = ROOT / raw_path
    if not path.is_file():
        raise SystemExit(f"FAIL {label} nao resolve: {raw_path}")

print("PASS registry liga policy, protocolo, metodo e ADR")
