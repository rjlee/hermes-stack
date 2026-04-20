#!/usr/bin/env bash
# -----------------------------------------------------------------
# bootstrap.sh - Runs all .sh scripts in scripts/ directory
# Runs at container startup before gateway starts
# -----------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/scripts"

if [[ ! -d "$SCRIPT_DIR" ]]; then
    echo "⚠️ No scripts/ directory found – nothing to run."
    exit 0
fi

echo "🔧 Running bootstrap scripts from $SCRIPT_DIR ..."

# Install Python dependencies first
if [[ -f "$SCRIPT_DIR/install-python-deps.sh" ]]; then
    echo "▶️ Running install-python-deps.sh"
    bash "$SCRIPT_DIR/install-python-deps.sh"
    echo "✅ install-python-deps.sh finished"
fi

for script in $(ls -1 "$SCRIPT_DIR"/*.sh 2>/dev/null | sort); do
    scriptname=$(basename "$script")
    # Skip python-deps (already run above)
    if [[ "$scriptname" == "install-python-deps.sh" ]]; then
        continue
    fi
    if [[ -f "$script" ]]; then
        echo "▶️ Executing $scriptname"
        bash "$script"
        echo "✅ $scriptname finished"
    else
        echo "⏭️ Skipping $scriptname (not a file)"
    fi
done

if [[ -d "/opt/data" ]]; then
    # Match HERMES_UID in docker-compose (1000) so host user can access
    chown -R 1000:1000 /opt/data
    echo "🔧 Fixed ownership of /opt/data to UID 1000"
    
    # Fix any files created by install scripts as UID 10000 (hermes user)
    # This handles files created by npm installs, skill installs, etc.
    find /opt/data -user 10000 -exec chown -h 1000:1000 {} \; 2>/dev/null || true
    echo "🔧 Fixed any stray UID 10000 files to UID 1000"
fi

echo "🎉 All bootstrap scripts have completed."
