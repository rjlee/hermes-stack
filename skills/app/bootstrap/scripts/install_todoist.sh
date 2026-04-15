#!/usr/bin/env bash
# -----------------------------------------------------------------
# install_todoist.sh
#   • Installs the Todoist CLI (npm @doist/todoist-cli)
#   • Installs the Todoist‑CLI Hermes skill via `td skill install`
#   • Persists the npm‑global bin directory in the user's PATH
#   • Designed to be invoked by the generic‑bootstrap skill
# -----------------------------------------------------------------

set -euo pipefail

# -----------------------------------------------------------------
# 0️⃣ Helper functions
# -----------------------------------------------------------------
add_path_if_missing() {
    # $1 = directory to add
    # $2 = file that should receive the export (e.g. ~/.bashrc)
    local dir="$1"
    local rcfile="$2"

    # Strip trailing slash for a clean comparison
    dir="${dir%/}"

    # Check whether the directory is already in the PATH
    if [[ ":$PATH:" == *":${dir}:"* ]]; then
        return 0    # already present – nothing to do
    fi

    # If the rcfile does not exist yet, create an empty one
    if [[ ! -f "${rcfile}" ]]; then
        touch "${rcfile}"
    fi

    # Guard against adding the same line twice (in case the user edited the file manually)
    if ! grep -Fxq "export PATH=\"${dir}:\$PATH\"" "${rcfile}"; then
        echo "export PATH=\"${dir}:\$PATH\"" >> "${rcfile}"
        echo "🔧 Added ${dir} to PATH in ${rcfile}"
    else
        echo "🔧 PATH line already present in ${rcfile}"
    fi
}

# -----------------------------------------------------------------
# 1️⃣ Put required binaries on the temporary PATH for *this* run
# -----------------------------------------------------------------
# Todoist‑CLI (npm‑global location – we will also persist this later)
export PATH="${HOME}/.npm-global/bin:${PATH}"

# Hermes CLI (the working virtual‑env binary – only needed now)
export PATH="/opt/hermes/.venv/bin:${PATH}"

# -----------------------------------------------------------------
# 2️⃣ Verify we can actually run the two commands we need
# -----------------------------------------------------------------
if command -v td >/dev/null; then
    echo "✅ td (Todoist CLI) found at $(command -v td)"
else
    echo "❌ td not found – aborting."
    exit 1
fi

if command -v hermes >/dev/null; then
    echo "✅ hermes CLI found at $(command -v hermes)"
else
    echo "⚠️ hermes CLI not found – skill install will still work via td."
fi

# -----------------------------------------------------------------
# 3️⃣ Install the Todoist CLI (npm) – user‑local, no sudo needed
# -----------------------------------------------------------------
NPM_PREFIX="${HOME}/.npm-global"
export NPM_CONFIG_PREFIX="${NPM_PREFIX}"
mkdir -p "${NPM_PREFIX}"/{bin,lib,node_modules}

echo "⚡ Installing Todoist‑CLI (npm) to ${NPM_PREFIX} ..."
npm i -g --silent @doist/todoist-cli

# Verify the install succeeded
if ! command -v td >/dev/null; then
    echo "❌ td still missing after npm install – aborting."
    exit 1
fi
echo "✅ Todoist‑CLI installed. td is now at $(command -v td)"

# -----------------------------------------------------------------
# 4️⃣ Persist the npm‑global bin directory in the user’s shell startup files
# -----------------------------------------------------------------
# Most interactive shells read either ~/.bashrc (bash) or ~/.zshrc (zsh).
# We also update ~/.profile because some login shells only source that.
# The helper function guarantees we never duplicate the line.

add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.bashrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.zshrc"
add_path_if_missing "${HOME}/.npm-global/bin" "${HOME}/.profile"

# -----------------------------------------------------------------
# 5️⃣ Install the Todoist‑CLI Hermes skill (universal agent)
# -----------------------------------------------------------------
echo "🔗 Installing the Todoist‑CLI Hermes skill (universal agent) via td..."
if td skill install universal; then
    echo "✅ Todoist‑CLI skill installed via td."
else
    echo "❌ td skill install failed – you may need to investigate manually."
    exit 1
fi

# -----------------------------------------------------------------
# 6️⃣ Verify the skill file exists where Hermes expects it
# -----------------------------------------------------------------
SKILL_PATH="${HOME}/.agents/skills/todoist-cli/SKILL.md"
if [[ -f "${SKILL_PATH}" ]]; then
    echo "🔎 Skill file found at ${SKILL_PATH}"
else
    echo "⚠️ Skill file not found at ${SKILL_PATH} – you may need to restart the Hermes agent."
fi

# -----------------------------------------------------------------
# 7️⃣ Final note
# -----------------------------------------------------------------
cat <<EOF

🎉 Todoist setup script completed successfully.

📌 The npm‑global bin directory (${HOME}/.npm-global/bin) has been added
    to the following shell‑initialisation files (if they exist):
    • ${HOME}/.bashrc
    • ${HOME}/.zshrc
    • ${HOME}/.profile

    **The change takes effect the next time a shell reads one of those files**
    – i.e. open a new terminal window or restart the Hermes agent.

🚀 You can now run the Todoist CLI directly:

    td --version
    td task list

🛠️ And you can invoke Todoist through Hermes:

    hermes exec td task list

EOF

exit 0
