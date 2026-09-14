#!/usr/bin/env bash
# -----------------------------------------------------------------
# 05-install-docker-cli.sh
#   Places a Docker CLI into /opt/data/.local/bin so every sandbox
#   container (which mounts /opt/data and has /opt/data/.local/bin
#   first on PATH) gets working `docker` commands against the shared
#   /var/run/docker.sock mounted by the terminal backend.
#
#   root-free: /opt/data is owned by the hermes runtime user.
#   idempotent: skips when the binary is already in place.
# -----------------------------------------------------------------

set -euo pipefail

DOCKER_DEST="/opt/data/.local/bin/docker"

if [ -x "${DOCKER_DEST}" ]; then
  echo "[bootstrap] docker CLI already at ${DOCKER_DEST} – skipping"
  exit 0
fi

SRC="/usr/bin/docker"
if [ ! -x "${SRC}" ]; then
  echo "[bootstrap] ERROR: ${SRC} not found; cannot provision docker CLI"
  exit 1
fi

mkdir -p "$(dirname "${DOCKER_DEST}")"
cp "${SRC}" "${DOCKER_DEST}"
chmod +x "${DOCKER_DEST}"
echo "[bootstrap] docker CLI provisioned at ${DOCKER_DEST}"
if command -v docker >/dev/null 2>&1; then
  echo "[bootstrap] docker CLI now available: $(docker --version 2>/dev/null || true)"
else
  echo "[bootstrap] docker CLI installed, but not on this process PATH (fine)"
fi