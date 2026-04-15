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

for script in "$(ls -1 "$SCRIPT_DIR"/*.sh 2>/dev/null | sort)"; do
    if [[ -f "$script" ]]; then
        echo "▶️ Executing $(basename "$script")"
        bash "$script"
        echo "✅ $(basename "$script") finished"
    else
        echo "⏭️ Skipping $(basename "$script") (not a file)"
    fi
done

echo "🎉 All bootstrap scripts have completed."
