#!/usr/bin/env bash
# -----------------------------------------------------------------
# install-opencode.sh
#   Installs the OpenCode CLI if not already present
#   Runs at container startup (runtime)
# -----------------------------------------------------------------

set -euo pipefail

if command -v opencode >/dev/null 2>&1; then
    echo "✅ OpenCode already installed – skipping"
    exit 0
fi

echo "[bootstrap] OpenCode not found → installing …"

OPEDIR="/usr/local/bin"
mkdir -p "${OPEDIR}"

echo "[bootstrap] Resolving latest release URL …"

LATEST_URL=""
URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
    | grep -o 'https://[^\"]*linux-x64-baseline\.tar\.gz' \
    | head -n 1)
if [ -n "$URL" ]; then LATEST_URL="$URL"; fi

if [ -z "$LATEST_URL" ]; then
    URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
        | grep -o 'https://[^\"]*linux-x64-musl[^\"]*\.tar\.gz' \
        | head -n 1)
    if [ -n "$URL" ]; then LATEST_URL="$URL"; fi
fi

if [ -z "${LATEST_URL}" ]; then
    echo "[bootstrap] ERROR: Failed to resolve download URL"
    exit 1
fi

echo "[bootstrap] Downloading from ${LATEST_URL}"

curl -fL -o /tmp/opencode.tar.gz "${LATEST_URL}"
tar -xzf /tmp/opencode.tar.gz -C "${OPEDIR}"

if [ -f "${OPEDIR}/opencode" ]; then
    chmod +x "${OPEDIR}/opencode"
else
    FOUND_BIN=$(find "${OPEDIR}" -type f -name opencode | head -n 1 || true)
    if [ -n "${FOUND_BIN}" ]; then
        chmod +x "${FOUND_BIN}"
        ln -sf "${FOUND_BIN}" "${OPEDIR}/opencode"
    else
        echo "[bootstrap] ERROR: opencode binary not found after extraction"
        exit 1
    fi
fi

rm -f /tmp/opencode.tar.gz

echo "[bootstrap] OpenCode installed to ${OPEDIR}"

OPENCODE_CONF_DIR="${HOME}/.config/opencode"
OPENCODE_CONF_FILE="${OPENCODE_CONF_DIR}/opencode.json"
if [ ! -f "${OPENCODE_CONF_FILE}" ]; then
    echo "[bootstrap] Creating minimal OpenCode config"
    mkdir -p "${OPENCODE_CONF_DIR}"
    cat > "${OPENCODE_CONF_FILE}" <<'EOF'
{
  "model": "opencode/gpt-5-nano"
}
EOF
    chmod 600 "${OPENCODE_CONF_FILE}"
else
    echo "[bootstrap] OpenCode config already present – skipping"
fi

if [[ -d "${HOME}/.config/opencode" ]]; then
    chown -R hermes:hermes "${HOME}/.config/opencode"
fi
