#!/usr/bin/env bash
set -euo pipefail

# Ensure backup directory exists
BACKUP_DIR="$(pwd)/backup"
mkdir -p "$BACKUP_DIR"

# Clean any existing backups for a clean test
rm -f "$BACKUP_DIR"/hermes-stack_*.tar.gz

# Create 10 dummy backups (older to newer)
for i in {1..10}; do
  ts=$(date -d "-$(($i)) days" +%Y%m%d_%H%M%S)
  touch "$BACKUP_DIR/hermes-stack_${ts}.tar.gz"
  # Ensure timestamps increase
  sleep 0.1
done

# Run backup with dry-run and retain 5
output=$(./hermes-stack backup --retain 5 --dry-run)

echo "$output"

# Check that it reports 5 files to prune (oldest 5)
if echo "$output" | grep -q "Dry‑run: the following 5 backup(s) would be removed"; then
  echo "✅ Dry‑run correctly identifies 5 old backups"
else
  echo "❌ Dry‑run did NOT identify correct number of old backups"
  exit 1
fi

# Now run actual prune (retain 5)
./hermes-stack backup --retain 5

remaining=$(ls -1 "$BACKUP_DIR"/hermes-stack_*.tar.gz | wc -l)
if [[ $remaining -eq 5 ]]; then
  echo "✅ After prune, exactly 5 backups remain as expected"
else
  echo "❌ After prune, expected 5 backups but found $remaining"
  exit 1
fi

# Cleanup
rm -rf "$BACKUP_DIR"

echo "All backup tests passed."
