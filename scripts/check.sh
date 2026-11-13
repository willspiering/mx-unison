#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
"${MX_UNISON_PYTHON:-/usr/bin/python3}" -B -m unittest discover -s test -p 'test_*.py'
node test/settings_model.js
node test/plain_hid_text.js
node test/desk_targets.js
git diff --check
git diff --cached --check
