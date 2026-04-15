#!/usr/bin/env bash
# -----------------------------------------------------------------
# install-curl.sh
#   Installs curl if not already present
#   Runs at container startup (runtime)
# -----------------------------------------------------------------

set -euo pipefail

if command -v curl >/dev/null 2>&1; then
    echo "✅ curl already installed – skipping"
    exit 0
fi

echo "[bootstrap] curl not found → installing …"

apt-get update -qq
apt-get install -yqq --no-install-recommends curl
rm -rf /var/lib/apt/lists/*

echo "✅ curl installed"
