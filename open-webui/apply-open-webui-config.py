#!/usr/bin/env python3
"""Apply declarative Open WebUI settings for the hermes-agent model.

Run inside the open-webui container (or with the webui.db path reachable).
Reads open-webui/config.json and applies it to the SQLite database:

  * model_features: force Open WebUI's native capabilities OFF on the
    hermes-agent model and remove them from defaultFeatureIds, so new chats
    don't get Open WebUI's own prompt wrappers (browser code interpreter,
    image gen, web search) competing with Hermes' tools/skills.
  * config: write ConfigVar values into the `config` table (JSON blob under
    `data`). The DB value wins over the env var in Open WebUI's ConfigVar
    resolution, so this is the reliable place to set them.

Idempotent: re-running is safe and reports what changed.

Usage:
    python3 apply-open-webui-config.py [--config PATH] [--db PATH] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
import time
from pathlib import Path

DEFAULT_CONFIG = Path("/opt/open-webui-config/config.json")
DEFAULT_DB = Path("/app/backend/data/webui.db")


def _load_config(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        sys.exit(f"config {path} is not a JSON object")
    return data


def _apply_model_features(cur: sqlite3.Cursor, spec: dict, dry: bool) -> list[str]:
    model_id = spec.get("model_id")
    if not model_id:
        return []
    row = cur.execute("SELECT meta FROM model WHERE id = ?", (model_id,)).fetchone()
    if row is None:
        return [f"model '{model_id}' not found in DB (skipped)"]
    meta = json.loads(row[0] or "{}")
    changes: list[str] = []

    caps = meta.setdefault("capabilities", {})
    for feat in spec.get("disable_capabilities", []):
        if caps.get(feat):
            caps[feat] = False
            changes.append(f"{model_id}: capabilities.{feat} -> false")

    defaults = meta.get("defaultFeatureIds") or []
    remove = set(spec.get("clear_default_feature_ids", []))
    new_defaults = [f for f in defaults if f not in remove]
    if new_defaults != defaults:
        meta["defaultFeatureIds"] = new_defaults
        changes.append(f"{model_id}: defaultFeatureIds {defaults} -> {new_defaults}")

    if changes and not dry:
        cur.execute("UPDATE model SET meta = ? WHERE id = ?",
                    (json.dumps(meta), model_id))
    return changes


def _apply_configvars(cur: sqlite3.Cursor, config: dict, dry: bool) -> list[str]:
    row = cur.execute("SELECT data FROM config ORDER BY id LIMIT 1").fetchone()
    # Open WebUI's State store: a single row holding a JSON blob under `data`.
    if row is None:
        blob: dict = {}
        row_id = 1
        insert = True
    else:
        blob = json.loads(row[0] or "{}")
        row_id = cur.execute("SELECT id FROM config ORDER BY id LIMIT 1").fetchone()[0]
        insert = False

    changes: list[str] = []
    for dotted, value in config.items():
        parts = dotted.split(".")
        node = blob
        for p in parts[:-1]:
            nxt = node.get(p)
            if not isinstance(nxt, dict):
                nxt = {}
                node[p] = nxt
            node = nxt
        leaf = parts[-1]
        if node.get(leaf) != value:
            changes.append(f"{dotted}: {node.get(leaf)!r} -> {value!r}")
            node[leaf] = value

    if changes and not dry:
        new_data = json.dumps(blob)
        if insert:
            cur.execute("INSERT INTO config (id, data, version, created_at, updated_at) "
                        "VALUES (?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                        (row_id, new_data))
        else:
            cur.execute("UPDATE config SET data = ?, updated_at = CURRENT_TIMESTAMP "
                        "WHERE id = ?", (new_data, row_id))
    return changes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=str(DEFAULT_CONFIG))
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cfg_path = Path(args.config)
    db_path = Path(args.db)
    if not cfg_path.exists():
        sys.exit(f"config not found: {cfg_path}")
    if not db_path.exists():
        sys.exit(f"open-webui DB not found: {db_path}")

    spec = _load_config(cfg_path)

    # Back up the DB once per run (webui.db is small; keep it simple).
    if not args.dry_run:
        backup = db_path.with_suffix(f".db.bak-{time.strftime('%Y%m%d-%H%M%S')}")
        try:
            shutil.copy2(db_path, backup)
            print(f"backup: {backup}")
        except OSError as e:
            print(f"WARNING: DB backup failed ({e}); continuing", file=sys.stderr)

    con = sqlite3.connect(str(db_path))
    try:
        cur = con.cursor()
        changes = []
        changes += _apply_model_features(cur, spec.get("model_features", {}), args.dry_run)
        changes += _apply_configvars(cur, spec.get("config", {}), args.dry_run)
        if not args.dry_run:
            con.commit()
    finally:
        con.close()

    if changes:
        verb = "would change" if args.dry_run else "changed"
        for c in changes:
            print(f"  {verb}: {c}")
    else:
        print("  already up to date — no changes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
