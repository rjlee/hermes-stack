#!/usr/bin/env bash
# -----------------------------------------------------------------
# install-life360.sh
#   Installs the Life360 CLI if not already present
#   Installs the Life360 skill to /opt/data/skills/ so hermes can see it
#   Runs at container startup (runtime)
# -----------------------------------------------------------------

set -euo pipefail

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

install_skill() {
    local L360_SKILL_DIR="/opt/data/skills/productivity/location-query"
    
    if [[ -f "$L360_SKILL_DIR/SKILL.md" ]]; then
        echo "✅ Life360 CLI skill already installed at $L360_SKILL_DIR/"
        return 0
    fi
    
    echo "[bootstrap] Installing Life360 CLI skill for universal agent…"
    
    if l360 skill install universal 2>&1; then
        mkdir -p "$L360_SKILL_DIR"
        if [[ -f "/root/.agents/skills/life360-cli/SKILL.md" ]]; then
            cp /root/.agents/skills/life360-cli/SKILL.md "$L360_SKILL_DIR/SKILL.md"
            chown hermes:hermes "$L360_SKILL_DIR/SKILL.md"
            echo "✅ Life360 CLI skill installed to $L360_SKILL_DIR/"
        else
            echo "⚠️ Skill file not found at /root/.agents/skills/life360-cli/SKILL.md"
        fi
    else
        echo "⚠️ l360 skill install failed (may need auth)"
    fi
}

# Check if Life360 CLI auth is configured via env var
check_auth() {
    if [[ -n "${LIFE360_AUTHORIZATION:-}" ]]; then
        echo "✅ LIFE360_AUTHORIZATION env var is set"
        return 0
    fi
    
    # Check for stored credentials
    if [[ -f "$HOME/.config/l360/credentials.json" ]] || l360 auth status >/dev/null 2>&1; then
        echo "✅ Life360 CLI credentials found"
        return 0
    fi
    
    return 1
}

# Install Life360 CLI if not present
if command -v l360 >/dev/null 2>&1; then
    echo "✅ Life360 CLI found at $(which l360)"
    check_auth || echo "⚠️ Life360 CLI not authenticated"
    install_skill
    exit 0
fi

echo "[bootstrap] Life360 CLI not found → installing …"

npm install -g life360-cli --force

if ! command -v l360 >/dev/null 2>&1; then
    echo "[bootstrap] ERROR: l360 not found after npm install"
    exit 1
fi

echo "✅ Life360 CLI installed"

NPM_GLOBAL_DIR="${HOME}/.npm-global"
if [[ -d "$NPM_GLOBAL_DIR" ]]; then
    chown -R hermes:hermes "$NPM_GLOBAL_DIR"
fi

add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.bashrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.zshrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.profile"

install_skill