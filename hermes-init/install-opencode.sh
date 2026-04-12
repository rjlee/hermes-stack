#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# Install the OpenCode CLI (only if it is not already present)
# -------------------------------------------------------------
if ! command -v opencode >/dev/null 2>&1; then
    echo "[hermes-init] opencode not found → installing …"

    # Ensure required tools exist
    apt-get update -qq && \
    apt-get install -yqq curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

    # Directory where we will place the binary
    OPEDIR="/usr/local/bin"
    mkdir -p "${OPEDIR}"

    # ---------------------------------------------------------
    # Resolve latest release download URL from GitHub
    # ---------------------------------------------------------
    echo "[hermes-init] resolving latest release URL …"

    # Try to get a statically linked "baseline" build first (no external lib dependencies)
    # Prefer the pure baseline (glibc) build; fall back to glibc‑specific, then musl, then baseline‑musl.
    # This ordering ensures we get a binary that works on a standard glibc system.
    # 1️⃣ baseline (no suffix)
    # 2️⃣ baseline‑glibc (if the repo provides an explicit glibc build)
    # 3️⃣ musl (current fallback)
    # 4️⃣ baseline‑musl (last resort)

    # Resolve the download URL by trying the most compatible builds first.
    LATEST_URL=""
    # 1️⃣ pure baseline (glibc‑compatible, no suffix)
    URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
        | grep -o 'https://[^\"]*linux-x64-baseline\.tar\.gz' \
        | head -n 1)
    if [ -n "$URL" ]; then LATEST_URL="$URL"; fi
    # 2️⃣ explicit baseline‑glibc if the repo provides it
    if [ -z "$LATEST_URL" ]; then
        URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
            | grep -o 'https://[^\"]*linux-x64-baseline-glibc[^\"]*\.tar\.gz' \
            | head -n 1)
        if [ -n "$URL" ]; then LATEST_URL="$URL"; fi
    fi
    # 3️⃣ musl‑linked build (fallback for musl environments)
    if [ -z "$LATEST_URL" ]; then
        URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
            | grep -o 'https://[^\"]*linux-x64-musl[^\"]*\.tar\.gz' \
            | head -n 1)
        if [ -n "$URL" ]; then LATEST_URL="$URL"; fi
    fi
    # 4️⃣ baseline‑musl as last resort
    if [ -z "$LATEST_URL" ]; then
        URL=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
            | grep -o 'https://[^\"]*linux-x64-baseline-musl[^\"]*\.tar\.gz' \
            | head -n 1)
        if [ -n "$URL" ]; then LATEST_URL="$URL"; fi
    fi

    # Validate URL
    if [ -z "${LATEST_URL}" ]; then
        echo "[hermes-init] ERROR: Failed to resolve download URL"
        exit 1
    fi

    echo "[hermes-init] downloading from ${LATEST_URL}"

    # ---------------------------------------------------------
    # Download and install
    # ---------------------------------------------------------
    curl -fL -o /tmp/opencode.tar.gz "${LATEST_URL}"

    tar -xzf /tmp/opencode.tar.gz -C "${OPEDIR}"

    # Ensure binary is executable (handle possible nested structure)
    if [ -f "${OPEDIR}/opencode" ]; then
        chmod +x "${OPEDIR}/opencode"
    else
        # fallback: find it if archive structure changed
        FOUND_BIN=$(find "${OPEDIR}" -type f -name opencode | head -n 1 || true)
        if [ -n "${FOUND_BIN}" ]; then
            chmod +x "${FOUND_BIN}"
            ln -sf "${FOUND_BIN}" "${OPEDIR}/opencode"
        else
            echo "[hermes-init] ERROR: opencode binary not found after extraction"
            exit 1
        fi
    fi

    rm -f /tmp/opencode.tar.gz

    echo "[hermes-init] opencode installed to ${OPEDIR}"

else
    echo "[hermes-init] opencode already available – skipping install"
fi

# ---------------------------------------------------------
# Ensure a minimal OpenCode config exists (free model, no API key)
# ---------------------------------------------------------
OPENCODE_CONF_DIR="${HOME}/.config/opencode"
OPENCODE_CONF_FILE="${OPENCODE_CONF_DIR}/opencode.json"
if [ ! -f "${OPENCODE_CONF_FILE}" ]; then
    echo "[hermes-init] creating minimal OpenCode config at ${OPENCODE_CONF_FILE}"
    mkdir -p "${OPENCODE_CONF_DIR}"
    cat > "${OPENCODE_CONF_FILE}" <<'EOF'
{
  "model": "opencode/gpt-5-nano"
}
EOF
    # Ensure the config file is readable (no secrets stored)
    chmod 600 "${OPENCODE_CONF_FILE}"
else
    echo "[hermes-init] OpenCode config already present – skipping config creation"
fi
