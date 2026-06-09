#!/usr/bin/env bash
# -----------------------------------------------------------------
# install-opencode.sh
#   Installs the OpenCode CLI if not already present
#   Ensures ~/.profile adds ~/.local/bin to PATH for login shells
#   Configures OpenRouter auth from env var
#   Runs at container startup (runtime)
# -----------------------------------------------------------------

set -euo pipefail

# ── Ensure ~/.profile includes ~/.local/bin in PATH ──────────────────
PROFILE="${HOME}/.profile"
LOCAL_BIN="${HOME}/.local/bin"

if [ -f "$PROFILE" ]; then
  if ! grep -qF "$LOCAL_BIN" "$PROFILE"; then
    echo "[bootstrap] Adding $LOCAL_BIN to $PROFILE"
    cat >> "$PROFILE" <<"PROFILEEOF"

# Added by hermes-stack bootstrap
case ":$PATH:" in
  *:/opt/data/.local/bin:*) ;;
  *) PATH="/opt/data/.local/bin:$PATH" ;;
esac
export PATH
PROFILEEOF
  fi
else
  echo "[bootstrap] Creating $PROFILE with $LOCAL_BIN in PATH"
  mkdir -p "$(dirname "$PROFILE")"
  cat > "$PROFILE" <<"PROFILEEOF"
# Added by hermes-stack bootstrap
case ":$PATH:" in
  *:/opt/data/.local/bin:*) ;;
  *) PATH="/opt/data/.local/bin:$PATH" ;;
esac
export PATH
PROFILEEOF
fi

# ── OpenCode config (runs every boot) ────────────────────────────────
OPENCODE_CONF_DIR="${HOME}/.config/opencode"
OPENCODE_CONF_FILE="${OPENCODE_CONF_DIR}/opencode.json"
mkdir -p "${OPENCODE_CONF_DIR}"

if [ -f "/opt/data/opencode.json" ]; then
    echo "[bootstrap] Using opencode.json from data volume"
    cp "/opt/data/opencode.json" "${OPENCODE_CONF_FILE}"
elif [ ! -f "${OPENCODE_CONF_FILE}" ]; then
    echo "[bootstrap] Creating minimal OpenCode config"
    cat > "${OPENCODE_CONF_FILE}" <<"JSONEOF"
{
  "model": "opencode/gpt-5-nano"
}
JSONEOF
else
    echo "[bootstrap] OpenCode config already present – skipping"
fi

chmod 600 "${OPENCODE_CONF_FILE}"
chown -R hermes:hermes "${HOME}/.config/opencode" 2>/dev/null || true

# ── Configure OpenRouter auth (runs every boot) ─────────────────────
# Register the OpenRouter API key from env so `opencode auth list`
# shows a credential (required by the Hermes opencode skill).
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  AUTH_DIR="${HOME}/.local/share/opencode"
  AUTH_FILE="${AUTH_DIR}/auth.json"
  mkdir -p "$AUTH_DIR"
  python3 << PYEOF
import json, os
f = "$AUTH_FILE"
auth = {}
if os.path.exists(f):
    with open(f) as fh:
        auth = json.load(fh)
auth["openrouter"] = {"type": "api", "key": "$OPENROUTER_API_KEY"}
with open(f, "w") as fh:
    json.dump(auth, fh, indent=2)
PYEOF
  chmod 600 "$AUTH_FILE"
  chown -R hermes:hermes "${HOME}/.local/share/opencode" 2>/dev/null || true
  echo "[bootstrap] OpenRouter credential configured from env"
fi

# ── OpenCode binary install (one-time) ──────────────────────────────
if command -v opencode >/dev/null 2>&1; then
    echo "[bootstrap] OpenCode already installed – skipping"
    exit 0
fi

echo "[bootstrap] OpenCode not found → installing …"

OPEDIR="${HOME}/.local/bin"
mkdir -p "${OPEDIR}"

echo "[bootstrap] Resolving latest release URL …"

LATEST_URL=""
URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
    | grep -o "https://[^\"]*linux-x64-baseline\.tar\.gz" \
    | head -n 1)
if [ -n "$URL" ]; then LATEST_URL="$URL"; fi

if [ -z "$LATEST_URL" ]; then
    URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
        | grep -o "https://[^\"]*linux-x64-musl[^\"]*\.tar\.gz" \
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
