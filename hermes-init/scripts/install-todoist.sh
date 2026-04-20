#!/usr/bin/env bash
# -----------------------------------------------------------------
# install-todoist.sh
#   Installs the Todoist CLI if not already present
#   Installs the Todoist skill to /opt/data/skills/ so hermes can see it
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
    local TD_SKILL_DIR="/opt/data/skills/productivity/todoist-cli"
    
    if [[ -f "$TD_SKILL_DIR/SKILL.md" ]]; then
        echo "✅ Todoist skill already installed at $TD_SKILL_DIR/"
        return 0
    fi
    
    echo "[bootstrap] Installing Todoist skill for universal agent…"
    
    if td skill install universal 2>&1; then
        mkdir -p "$TD_SKILL_DIR"
        if [[ -f "/root/.agents/skills/todoist-cli/SKILL.md" ]]; then
            cp /root/.agents/skills/todoist-cli/SKILL.md "$TD_SKILL_DIR/SKILL.md"
            chown hermes:hermes "$TD_SKILL_DIR/SKILL.md"
            echo "✅ Todoist skill installed to $TD_SKILL_DIR/"
        else
            echo "⚠️ Skill file not found at /root/.agents/skills/todoist-cli/SKILL.md"
        fi
    else
        echo "⚠️ td skill install failed (may need auth)"
    fi
}

if command -v td >/dev/null 2>&1; then
    if [[ -f "$HOME/.npm-global/bin/td" ]] || which td | grep -q npm; then
        echo "✅ Todoist CLI already installed"
    else
        echo "✅ Todoist CLI found at $(which td)"
    fi
    install_skill
    exit 0
fi

echo "[bootstrap] Todoist CLI not found → installing …"

npm install -g @doist/todoist-cli

if ! command -v td >/dev/null 2>&1; then
    echo "[bootstrap] ERROR: td not found after npm install"
    exit 1
fi

echo "✅ Todoist CLI installed"

NPM_GLOBAL_DIR="${HOME}/.npm-global"
if [[ -d "$NPM_GLOBAL_DIR" ]]; then
    chown -R hermes:hermes "$NPM_GLOBAL_DIR"
fi

add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.bashrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.zshrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.profile"

install_skill
