#!/usr/bin/env bash
set -euo pipefail

BRIDGE_DIR="/opt/hermes/scripts/whatsapp-bridge"

if [[ -d "$BRIDGE_DIR/node_modules/@whiskeysockets/baileys" ]]; then
    exit 0
fi

echo "[bootstrap] WhatsApp bridge: reinstalling dependencies from $BRIDGE_DIR …"
rm -rf "$BRIDGE_DIR/node_modules" "$BRIDGE_DIR/package-lock.json"
cd "$BRIDGE_DIR" && npm install --no-audit --no-fund
echo "[bootstrap] WhatsApp bridge: dependencies installed"
