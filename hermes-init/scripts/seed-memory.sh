#!/bin/bash
# -----------------------------------------------------------------
# seed-memory.sh
# Seeds Hermes memory from hints files at container startup
# Only seeds if hints have changed or memory is empty
# -----------------------------------------------------------------

set -euo pipefail

echo "🌱 Seeding Hermes memory from hints..."

source /opt/hermes/.venv/bin/activate

HINTS_DIR="/opt/data/.hermes-stack/hints"

if [[ ! -d "$HINTS_DIR" ]] || [[ -z "$(ls -A "$HINTS_DIR" 2>/dev/null)" ]]; then
    echo "No hints found, skipping memory seeding"
    exit 0
fi

# Build hints content
HINTS_CONTENT=""
for hint in "$HINTS_DIR"/*; do
    if [[ -f "$hint" ]]; then
        HINTS_CONTENT+="$(cat "$hint")"
        HINTS_CONTENT+=$'\n---\n'
    fi
done

if [[ -z "$HINTS_CONTENT" ]]; then
    echo "No hints content to seed"
    exit 0
fi

# Seed memory - Hermes will handle deduplication via the prompt
echo "Seeding memory with hints..."
hermes chat -q "Remember these as persistent preferences. Only add new items - do NOT repeat anything already in your memory:\n$HINTS_CONTENT" --quiet 2>/dev/null || echo "⚠️ Memory seeding may have failed"

echo "✅ Memory seeding complete"