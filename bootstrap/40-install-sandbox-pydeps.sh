#!/usr/bin/env bash
# -----------------------------------------------------------------
# 40-install-sandbox-pydeps.sh
#   Installs Python packages needed by skills into the PERSISTENT
#   sandbox site-packages directory (/opt/data/.local/lib/python3.11/
#   site-packages). The execute_code / terminal sandbox image ships a
#   bare Python with no openpyxl/xlrd; the persistent dir is bind-mounted
#   into every sandbox and is also placed on PYTHONPATH via
#   TERMINAL_DOCKER_EXTRA_ARGS, so bare `python3` and the bundled
#   productivity/xlsx scripts work there.
#
#   Runs at container startup (runtime), idempotently.
# -----------------------------------------------------------------

set -euo pipefail

TARGET="/opt/data/.local/lib/python3.11/site-packages"
MARKER="${TARGET}/.hermes-sandbox-pydeps.ok"

# Packages the spreadsheet / document skills need. Keep this list minimal.
PKGS=("openpyxl" "xlrd<2.0")

if [ -f "$MARKER" ]; then
  echo "[bootstrap] sandbox pydeps already installed (marker present) — skipping"
  exit 0
fi

mkdir -p "$TARGET"

# The gateway image ships uv; python3 -m pip may not exist. Prefer uv.
echo "[bootstrap] Installing sandbox pydeps into $TARGET"
if command -v uv >/dev/null 2>&1; then
  uv pip install --quiet --target "$TARGET" "${PKGS[@]}"
elif python3 -m pip --version >/dev/null 2>&1; then
  python3 -m pip install --quiet --target "$TARGET" "${PKGS[@]}"
elif command -v pip3 >/dev/null 2>&1; then
  pip3 install --quiet --target "$TARGET" "${PKGS[@]}"
else
  echo "[bootstrap] WARNING: no uv/pip available — sandbox pydeps NOT installed" >&2
  exit 0
fi

# Smoke test
if PYTHONPATH="$TARGET" python3 -c "import openpyxl, xlrd" 2>/dev/null; then
  touch "$MARKER"
  echo "[bootstrap] sandbox pydeps OK (openpyxl + xlrd)"
else
  echo "[bootstrap] WARNING: import smoke test failed (packages may target a different python)" >&2
fi
