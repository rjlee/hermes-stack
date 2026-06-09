#!/usr/bin/env bash
set -euo pipefail

if command -v l360 >/dev/null 2>&1; then
    exit 0
fi

echo "[bootstrap] Installing life360-cli …"
npm install -g --prefix /opt/data/.local life360-cli@latest
