#!/usr/bin/env bash
# -----------------------------------------------------------------
# 55-install-doc-tools.sh
#   Provision document / scan / conversion tooling beyond the OCR+PDF
#   core (see 50-install-ocr.sh):
#     apt: unpaper, imagemagick, libheif-examples (heif-convert),
#          ghostscript, qpdf, pandoc, libimage-exiftool-perl (exiftool)
#     pip: python-docx, python-pptx, openpyxl, xlrd, odfpy, ocrmypdf
#          (into /opt/hermes/.venv -> fixes the docx/pptx/xlsx skills)
#
#   Same elevation model as 50-install-ocr.sh: runs as unprivileged
#   hermes at gateway:startup, elevates via the hermes SSH key ->
#   host docker exec -u 0. Idempotent per component.
# -----------------------------------------------------------------

set -euo pipefail

SSH_KEY="/opt/data/.ssh/id_ed25519"
KNOWN_HOSTS="/opt/data/.ssh/known_hosts"
VENV="/opt/hermes/.venv"
VENV_PY="${VENV}/bin/python3"
APT_PKGS=(unpaper imagemagick libheif-examples ghostscript qpdf pandoc libimage-exiftool-perl)
PY_PKGS=(python-docx python-pptx openpyxl xlrd==1.2.0 odfpy ocrmypdf)

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

# --- system tools ---
need_apt=0
for b in unpaper magick heif-convert gs qpdf pandoc exiftool; do
  command -v "$b" >/dev/null 2>&1 || need_apt=1
done
if [ "$need_apt" = 1 ]; then
  echo "[bootstrap] apt-installing: ${APT_PKGS[*]}"
  if run_root "docker exec -e DEBIAN_FRONTEND=noninteractive -u 0 ${SELF} sh -c 'apt-get update -qq && apt-get install -y --no-install-recommends ${APT_PKGS[*]}'"; then
    echo "[bootstrap] doc tools installed"
  else
    echo "[bootstrap] WARNING: apt install failed" >&2
    rc=1
  fi
else
  echo "[bootstrap] doc tools already present"
fi

# --- python libs for the docx / pptx / xlsx skills + ocrmypdf ---
if "$VENV_PY" -c "import docx, pptx, openpyxl, xlrd, odf, ocrmypdf" >/dev/null 2>&1; then
  echo "[bootstrap] office/pdf python deps already present"
else
  echo "[bootstrap] uv-installing into venv: ${PY_PKGS[*]}"
  if run_root "docker exec -u 0 ${SELF} sh -c '${UV_LOOKUP}; exec \"\$UV_BIN\" pip install --quiet --python ${VENV} ${PY_PKGS[*]}'"; then
    echo "[bootstrap] office/pdf python deps installed"
  else
    echo "[bootstrap] WARNING: uv pip install failed" >&2
    rc=1
  fi
fi

# --- report ---
for b in unpaper magick heif-convert gs qpdf pandoc exiftool; do
  if command -v "$b" >/dev/null 2>&1; then
    echo "[bootstrap] ok: $b"
  else
    echo "[bootstrap] WARNING: missing $b" >&2; rc=1
  fi
done
if "$VENV_PY" -c "import docx, pptx, openpyxl, xlrd, odf, ocrmypdf" >/dev/null 2>&1; then
  echo "[bootstrap] office/pdf python deps OK"
else
  echo "[bootstrap] WARNING: office/pdf python deps import failed" >&2; rc=1
fi

exit "$rc"
