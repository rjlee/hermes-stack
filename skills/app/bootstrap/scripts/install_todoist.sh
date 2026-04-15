#!/usr/bin/env bash
# -----------------------------------------------------------------
# install_todoist.sh
#   • Installs the Todoist CLI (npm @doist/todoist-cli)
#   • Installs the Todoist‑CLI Hermes skill via `td skill install`
#   • Designed to be invoked by the generic‑bootstrap skill
# -----------------------------------------------------------------

# ---------------------------------------------------------------
# 0️⃣ Fail fast on any error, treat unset vars as errors
# ---------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------
# 1️⃣ Add required binaries to PATH
# ---------------------------------------------------------------
# Todoist‑CLI (npm‑global location)
export PATH="${HOME}/.npm-global/bin:${PATH}"

# Hermes CLI (the working virtual‑env binary)
export PATH="/opt/hermes/.venv/bin:${PATH}"

# ---------------------------------------------------------------
# 2️⃣ Verify the binaries we need are actually reachable
# ---------------------------------------------------------------
if command -v td >/dev/null; then
    echo "✅ td (Todoist CLI) found at $(command -v td)"
else
    echo "❌ td not found – aborting."
    exit 1
fi

if command -v hermes >/dev/null; then
    echo "✅ hermes CLI found at $(command -v hermes)"
else
    echo "⚠️ hermes CLI not found – the script will still install the skill via td."
fi

# ---------------------------------------------------------------
# 3️⃣ Install the Todoist CLI (npm) – user‑local, no sudo needed
# ---------------------------------------------------------------
NPM_PREFIX="${HOME}/.npm-global"
export NPM_CONFIG_PREFIX="${NPM_PREFIX}"
mkdir -p "${NPM_PREFIX}"/{bin,lib,node_modules}

echo "⚡ Installing Todoist‑CLI (npm) to ${NPM_PREFIX} ..."
npm i -g --silent @doist/todoist-cli

# Double‑check the binary is now on PATH after the npm install
if ! command -v td >/dev/null; then
    echo "❌ td still missing after npm install – aborting."
    exit 1
fi
echo "✅ Todoist‑CLI installed. td is now at $(command -v td)"

# ---------------------------------------------------------------
# 4️⃣ Install the Hermes skill that ships with the Todoist CLI
# ---------------------------------------------------------------
# The Todoist‑CLI includes a built‑in installer that copies the
# skill into the universal agent directory (~/.agents/).
echo "🔗 Installing the Todoist‑CLI Hermes skill (universal agent) via td..."
if td skill install universal; then
    echo "✅ Todoist‑CLI skill installed via td."
else
    echo "❌ td skill install failed – you may need to investigate manually."
    exit 1
fi

# ---------------------------------------------------------------
# 5️⃣ Verify that the skill files now exist where Hermes expects them
# ---------------------------------------------------------------
SKILL_PATH="${HOME}/.agents/skills/todoist-cli/SKILL.md"
if [[ -f "${SKILL_PATH}" ]]; then
    echo "🔎 Skill file found at ${SKILL_PATH}"
else
    echo "⚠️ Skill file not found at ${SKILL_PATH} – you may need to restart the Hermes agent."
fi

# ---------------------------------------------------------------
# 6️⃣ Done
# ---------------------------------------------------------------
echo "🎉 Todoist setup script completed successfully."
exit 0
