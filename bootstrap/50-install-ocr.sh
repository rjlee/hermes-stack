#!/usr/bin/env bash
# -----------------------------------------------------------------
# 50-install-ocr.sh
#   Provision OCR + PDF document tooling into the gateway container:
#     - tesseract-ocr (+eng)   -> image / scanned-page OCR
#     - poppler-utils          -> pdftotext / pdftoppm / pdfinfo
#                                 (text extraction + page rasterisation)
#     - pypdf, pdfplumber, reportlab, pypdfium2, pymupdf, pymupdf4llm
#                              -> the builtin productivity/pdf skill scripts
#
#   Runs as the unprivileged hermes user (uid 10000) at gateway:startup.
#   Hermes has no in-container root and no sudo, but it DOES hold the
#   hermes SSH key to docker.home (/opt/data/.ssh), so we elevate by
#   asking the host docker daemon to run apt/uv inside THIS container as
#   uid 0. Idempotent per component, so it re-provisions automatically
#   after a container recreate (apt + venv site-packages live in the
#   container layer and are not persisted).
# -----------------------------------------------------------------

set -euo pipefail

SSH_KEY="/opt/data/.ssh/id_ed25519"
KNOWN_HOSTS="/opt/data/.ssh/known_hosts"
VENV="/opt/hermes/.venv"
VENV_PY="${VENV}/bin/python3"
APT_PKGS=(tesseract-ocr tesseract-ocr-eng poppler-utils)
PY_PKGS=(pypdf pdfplumber reportlab pypdfium2 pymupdf pymupdf4llm)

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

rc=0

# --- system binaries (tesseract + poppler) ---
need_apt=0
command -v tesseract >/dev/null 2>&1 || need_apt=1
command -v pdftotext >/dev/null 2>&1 || need_apt=1
if [ "$need_apt" = 1 ]; then
  echo "[bootstrap] apt-installing: ${APT_PKGS[*]}"
  if run_root "docker exec -e DEBIAN_FRONTEND=noninteractive -u 0 ${SELF} sh -c 'apt-get update -qq && apt-get install -y --no-install-recommends ${APT_PKGS[*]}'"; then
    echo "[bootstrap] system packages installed"
  else
    echo "[bootstrap] WARNING: apt install failed" >&2
    rc=1
  fi
else
  echo "[bootstrap] tesseract + poppler already present"
fi

# --- python libs for the productivity/pdf skill ---
if "$VENV_PY" -c "import pypdf, pdfplumber, reportlab, pypdfium2, pymupdf, pymupdf4llm" >/dev/null 2>&1; then
  echo "[bootstrap] pdf python deps already present"
else
  echo "[bootstrap] uv-installing into venv: ${PY_PKGS[*]}"
  if run_root "docker exec -u 0 ${SELF} sh -c '${UV_LOOKUP}; exec \"\$UV_BIN\" pip install --quiet --python ${VENV} ${PY_PKGS[*]}'"; then
    echo "[bootstrap] pdf python deps installed"
  else
    echo "[bootstrap] WARNING: uv pip install failed" >&2
    rc=1
  fi
fi

# --- report ---
if command -v tesseract >/dev/null 2>&1; then
  echo "[bootstrap] tesseract: $(tesseract --version 2>&1 | head -1)"
else
  echo "[bootstrap] WARNING: tesseract missing" >&2; rc=1
fi
if command -v pdftotext >/dev/null 2>&1; then
  echo "[bootstrap] poppler: $(pdftotext -v 2>&1 | head -1)"
else
  echo "[bootstrap] WARNING: poppler missing" >&2; rc=1
fi
if "$VENV_PY" -c "import pypdf, pdfplumber, reportlab, pypdfium2, pymupdf, pymupdf4llm" >/dev/null 2>&1; then
  echo "[bootstrap] pdf python deps OK"
else
  echo "[bootstrap] WARNING: pdf python deps import failed" >&2; rc=1
fi

exit "$rc"
