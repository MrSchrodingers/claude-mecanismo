#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1

python3 orchestration/render.py --check
python3 tests/unit/methodology.py
bash tests/unit/repository-hygiene.sh
