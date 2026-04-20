#!/bin/bash
# -----------------------------------------------------------------
# install-python-deps.sh
#   Installs Python dependencies needed by other scripts
# -----------------------------------------------------------------

set -euo pipefail

PYDEPTS_DIR="/opt/data/.hermes-stack/pydeps"

install_pyyaml() {
    if python3 -c "import yaml" 2>/dev/null; then
        echo "✅ pyyaml already installed"
        return 0
    fi
    
    echo "[bootstrap] Installing pyyaml..."
    
    # Try apt first
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq python3-yaml >/dev/null 2>&1 && echo "✅ pyyaml installed" && return 0
    fi
    
    # Try pip
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install --quiet pyyaml && echo "✅ pyyaml installed" && return 0
    fi
    
    # Try python3 -m pip
    python3 -m pip install --quiet pyyaml 2>/dev/null && echo "✅ pyyaml installed" && return 0
    
    echo "⚠️ Could not install pyyaml"
    return 1
}

install_pyyaml
mkdir -p "$PYDEPTS_DIR"
touch "$PYDEPTS_DIR/.installed"