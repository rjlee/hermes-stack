#!/usr/bin/env bash
# -----------------------------------------------------------------
# install-todoist.sh
#   Installs the Todoist CLI if not already present
#   Runs at container startup (runtime)
# -----------------------------------------------------------------

set -euo pipefail

if command -v td >/dev/null 2>&1; then
    echo "✅ Todoist CLI already installed – skipping"
    exit 0
fi

echo "[bootstrap] Todoist CLI not found → installing …"

npm install -g @doist/todoist-cli

if ! command -v td >/dev/null 2>&1; then
    echo "[bootstrap] ERROR: td not found after npm install"
    exit 1
fi

echo "✅ Todoist CLI installed"

add_path_if_missing() {
    local dir="$1"
    local rcfile="$2"
    dir="${dir%/}"
    if [[ ! -f "${rcfile}" ]]; then
        touch "${rcfile}"
    fi
    if ! grep -Fxq "export PATH=\"${dir}:\$PATH\"" "${rcfile}"; then
        echo "export PATH=\"${dir}:\$PATH\"" >> "${rcfile}"
    fi
}

add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.bashrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.zshrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.profile"

if command -v td >/dev/null 2>&1; then
    echo "[bootstrap] Installing Todoist skill for universal agent…"
    td skill install universal || echo "⚠️ Skill install failed (may need auth)"
    echo "✅ Todoist skill installed"
else
    echo "⚠️ td not available – skipping skill install"
fi
