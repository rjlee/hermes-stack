#!/usr/bin/env bash
set -euo pipefail

if command -v td >/dev/null 2>&1; then
    exit 0
fi

echo "[bootstrap] Installing @doist/todoist-cli …"
npm install -g --prefix /opt/data/.local @doist/todoist-cli
