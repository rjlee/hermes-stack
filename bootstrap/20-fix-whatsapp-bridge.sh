#!/usr/bin/env bash
# -----------------------------------------------------------------
# 20-fix-whatsapp-bridge.sh
#   Ensures the WhatsApp bridge runtime dependencies are present.
#
#   The bridge RUNS from /opt/data/scripts/whatsapp-bridge (seeded
#   into the hermes data volume and owned by the hermes runtime user),
#   NOT from the root-owned image copy at /opt/hermes/scripts/...,
#   which was being targeted by an earlier version of this script and
#   could never be written by the non-root bootstrap hook.
#
#   root-free: works entirely inside $HERMES_HOME (/opt/data).
#   idempotent: no-ops once the baileys runtime is installed.
# -----------------------------------------------------------------

set -euo pipefail

BRIDGE_DIR="/opt/data/scripts/whatsapp-bridge"
IMAGE_DIR="/opt/hermes/scripts/whatsapp-bridge"

if [ -d "${BRIDGE_DIR}/node_modules/@whiskeysockets/baileys" ]; then
  echo "[bootstrap] WhatsApp bridge: runtime dependencies present - skipping"
  exit 0
fi

# Fresh data volume: seed the bridge source from the image first.
if [ ! -d "${BRIDGE_DIR}" ] && [ -d "${IMAGE_DIR}" ]; then
  echo "[bootstrap] WhatsApp bridge: seeding runtime from ${IMAGE_DIR}"
  mkdir -p "$(dirname "${BRIDGE_DIR}")"
  cp -a "${IMAGE_DIR}" "${BRIDGE_DIR}"
fi

if [ ! -f "${BRIDGE_DIR}/package.json" ]; then
  echo "[bootstrap] ERROR: no package.json in ${BRIDGE_DIR}" >&2
  exit 1
fi

echo "[bootstrap] WhatsApp bridge: reinstalling dependencies in ${BRIDGE_DIR} ..."
rm -rf "${BRIDGE_DIR}/node_modules" "${BRIDGE_DIR}/package-lock.json"
( cd "${BRIDGE_DIR}" && npm install --no-audit --no-fund )
echo "[bootstrap] WhatsApp bridge: dependencies installed"