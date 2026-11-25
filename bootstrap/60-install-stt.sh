#!/usr/bin/env bash
# -----------------------------------------------------------------
# 60-install-stt.sh
#   Provision local speech-to-text (faster-whisper) so WhatsApp /
#   gateway voice notes are transcribed. config.yaml already sets
#   stt.provider: local and stt.local.model: small; this only installs
#   the engine. The model (~460 MB for "small") is downloaded on first
#   transcription and cached under /opt/data/.cache/huggingface.
#
#   Same elevation model as the other 5x scripts: unprivileged hermes at
#   gateway:startup, elevates via the hermes SSH key -> host docker exec.
# -----------------------------------------------------------------

set -euo pipefail

SSH_KEY="/opt/data/.ssh/id_ed25519"
KNOWN_HOSTS="/opt/data/.ssh/known_hosts"
VENV="/opt/hermes/.venv"
VENV_PY="${VENV}/bin/python3"
PY_PKGS=(faster-whisper)

if [ ! -r "$SSH_KEY" ]; then
  echo "[bootstrap] ERROR: hermes SSH key not readable at $SSH_KEY" >&2
  exit 1
fi

SELF="$(hostname)"
run_root() {
  ssh -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$KNOWN_HOSTS" \
      -o ConnectTimeout=10 \
      root@docker.home "$1"
}

# uv lives under /opt/hermes/tools/uv-<version>-linux-x64/uv but is not on
# root's PATH inside `docker exec`. Locate it in the target container.
UV_LOOKUP='UV_BIN=""; for u in /opt/hermes/tools/uv-*/uv; do [ -x "$u" ] && UV_BIN="$u" && break; done; [ -n "$UV_BIN" ] || UV_BIN=uv'

if "$VENV_PY" -c "import faster_whisper" >/dev/null 2>&1; then
  echo "[bootstrap] faster-whisper already present"
else
  echo "[bootstrap] uv-installing into venv: ${PY_PKGS[*]}"
  if run_root "docker exec -u 0 ${SELF} sh -c '${UV_LOOKUP}; exec \"\$UV_BIN\" pip install --quiet --python ${VENV} ${PY_PKGS[*]}'"; then
    echo "[bootstrap] faster-whisper installed"
  else
    echo "[bootstrap] WARNING: uv pip install failed" >&2
    exit 1
  fi
fi

if "$VENV_PY" -c "import faster_whisper; print('[bootstrap] faster-whisper', faster_whisper.__version__)"; then
  exit 0
else
  echo "[bootstrap] WARNING: faster_whisper import failed" >&2
  exit 1
fi
