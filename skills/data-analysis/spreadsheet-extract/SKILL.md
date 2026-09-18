---
name: spreadsheet-extract
title: Spreadsheet Extraction (formulas + values)
description: >-
  Spreadsheet attached — 'why does X differ from Y?', 'what formula?',
  'dump cells', 'show source'. NEVER answer from RAG alone: openpyxl
  reads the whole .xlsx/.xls/.csv with formulas + cached values +
  defined names; RAG snippets routinely miss whole sheets.
version: 1.0.0
platforms: [linux]
---

# Spreadsheet extraction

## TL;DR — the first thing to try

You have terminal access to the hermes gateway. The user's uploaded file
is on disk at `/opt/uploads/`. The file's precise name looks like
`<uuid4>_<safe-original-filename>.xlsx`. Run exactly these two commands
via the `terminal` tool, working directory anywhere:

```bash
ls -lt /opt/uploads/ | head -5
```

Then run the helper against the newest matching file:

```bash
python3 /opt/data/skills/data-analysis/spreadsheet-extract/scripts/extract.py \
  "/opt/uploads/<uuid4>_<safe-original-name.xlsx>" --mode both
```

The first command ALWAYS works (the directory exists on the gateway).
If the directory is empty, then and only then ask the user to re-upload.

**The RAG citation you saw in the chat history is NOT the source of
truth.** open-webui auto-runs a vector retrieval over uploaded files and
splices the top-k chunks into the user message as `sources`. That
retrieval is best-effort: it usually contains only the most-summary-like
sheet (Net Worth / Financial Health / Cover), it may completely miss
sheets the user is asking about, and the chunks it returns are
re-flowed text with newlines in odd places. NEVER cite the RAG numbers
as authoritative. ALWAYS run the helper to read the real workbook.

## Purpose

When the user asks any question about a spreadsheet attachment (data,
formulas, structure, comparative analysis, defined names, etc.), locate
the file on disk, extract every formula and the last cached computed
value, plus defined names, and present the answer.

## Why this skill exists instead of using the RAG citation alone

Open WebUI's RAG feature extracts the top-k chunks from each
attachment and surfaces them as `sources` in the user message. For
spreadsheets this is **almost always insufficient**:

1. The chunking is text-based, not sheet-aware. A 200k-cell workbook
   produces dozens of chunks; only 1–3 typically surface, and they
   tend to come from whichever sheet has the most narrative text
   (often "Net Worth Summary" or "Cover" — *not* the sheet the user
   is asking about).
2. Formulas are flattened to their cached values; the source formula is
   lost. So a question like "why are these two values different?" can
   never be answered from RAG alone — the formulas are missing.
3. Defined names, sheet-scoped calculations, and cross-sheet references
   are not chunked at all.

The helper reads the whole file with openpyxl and emits formulas + cached
values + defined names. It is the only authoritative way to answer a
spreadsheet question.

## Procedure

1. **Locate the file.** `terminal` tool:

   ```bash
   ls -lt /opt/uploads/
   ```

   - Pick the newest entry whose original-name suffix (after `<uuid>_`)
     matches a file the user mentioned. If the user didn't name a file
     but attached exactly one, use the newest matching extension.
   - If multiple matches and you cannot disambiguate, ask the user.
   - If `/opt/uploads/` is empty (zero output), the upload didn't
     persist; ask the user to re-upload. **Do not** fall back to other
     paths, sandbox containers, browser sessions, or "context data".

2. **Run the helper.** `terminal` tool, capturing stdout:

   ```bash
   python3 /opt/data/skills/data-analysis/spreadsheet-extract/scripts/extract.py \
     "/opt/uploads/<uuid>_<safe_name>" --mode both
   ```

   `python3` (the sandbox system interpreter) already has `openpyxl` and
   `xlrd` on its `PYTHONPATH`. The packages live in the persistent,
   bind-mounted directory `/opt/data/.local/lib/python3.11/site-packages`
   and are put on `PYTHONPATH` by `TERMINAL_DOCKER_EXTRA_ARGS` /
   `terminal.docker_extra_args`. `./hermes-stack install bootstraps`
   installs them (bootstrap script `40-install-sandbox-pydeps.sh`).

   If `ModuleNotFoundError: No module named 'openpyxl'` appears, the
   packages are missing from that dir. Reinstall them with:

   ```bash
   pip install --target /opt/data/.local/lib/python3.11/site-packages \
     openpyxl 'xlrd<2.0'
   ```

   (or run `./hermes-stack install bootstraps && docker compose restart hermes`
   from the host). Then re-run the helper command from the top of step 2.

   The helper emits a single JSON object on stdout:

   ```json
   {
     "path": "...",
     "engine": "openpyxl|xlrd|csv",
     "mode": "formulas|values|both",
     "sheets": [
       {
         "name": "Sheet1",
         "dimensions": [42, 7],
         "max_row": 42,
         "max_col": 7,
         "cells": [
           {"coord": "A1", "formula": null, "value": "Header"},
           {"coord": "B3", "formula": "A1*2", "value": 14}
         ],
         "named_ranges": [
           {"name": "TaxRate", "coord": "B2", "formula": null, "value": 0.2}
         ]
       }
     ],
     "warnings": []
   }
   ```

3. **Parse the JSON (use `json.loads`) and answer the question.**
   Don't dump the whole JSON in the response — that's noisy and
   expensive. Read the relevant cells, look up the formulas, and
   **answer the user's actual question**. For "why does X differ from
   Y" questions, the answer is usually: trace X back through its
   formula chain, trace Y back through its formula chain, and
   explain the structural difference (different SUMIF criteria,
   different sheet scopes, different accounting adjustments, etc.).

   Cell entry shape:
   - `coord` (e.g. "A1")
   - `formula` (formula string with leading "=" stripped, or literal
     value if non-formula, or null)
   - `formula_display` (set when `formula` holds a non-string literal
     like a datetime or ArrayFormula ref)
   - `formula_type` (set on literal values: "string", "number",
     "boolean", "datetime", "array_formula", "rich_text")
   - `value` (cached computed value, or null if uncached)
   - `value_display` / `value_type` (parallel keys for the value side)

4. **Verify before answering:** confirm `sheets` is non-empty and at
   least one cell row per non-empty sheet. Spot-check that the cells
   referenced in your answer actually contain the values/ formulas
   you cited. If a formula has a null cached value, mention this so
   the user knows the workbook was last saved by openpyxl alone (not
   by Excel) and re-evaluation is needed.

## Worked example (from a real session)

User: "On the 'Financial Health' sheet, why does the value of 'Safe
Assets (Non-Volatile)' differ from the value of 'Income Bridge' on the
'AssetDistribution' sheet?"

Skill action:

1. `ls -lt /opt/uploads/ | head -3`
   → `e972b47a-9c2d-44ca-8cfe-2050b00102cc_Retirement - 2026.xlsx`
2. `python3 /opt/data/skills/data-analysis/spreadsheet-extract/scripts/extract.py
   "/opt/uploads/e972b47a-…_Retirement - 2026.xlsx" --mode both | jq`
3. Examine `Financial Health!B7 = Balances!H2` and `AssetDistribution!N1 =
   SUM(N10:N13)`. Trace each formula:
   - `Balances!H2 = SUMIF(D:D,"N",B:B) + K1 + K2`. K1 = -50,141, K2 =
     +195,518. So H2 = (sum of non-volatile balances) + 145,377.
   - `AssetDistribution!N1 = N10+N11+N12+N13 = F23 + F26 + F27 +
     Balances!H5`. These are specific earmarked bridge assets: L&G
     Cash Trust, Royal London STMM, L&G Pension balance, and all
     Type="C" cash balances.
4. Answer: explain that B7 is "the entire non-volatile Balances
   position" (balance-sheet view) while N1 is "specific earmarked
   bridge assets" (cash-flow planning view), and itemise what each
   component contributes to the 44,307 difference.

## Do not do this

The transcript of a recent failed attempt shows the model:
- Saw the RAG citation containing the Financial Health Net Worth
  Summary.
- Answered from the RAG chunk alone, with no terminal/execute_code calls.
- Concluded "I don't have access to the Income Bridge sheet" — when
  the helper would have surfaced it instantly.

The actual situation is the opposite:

- The file **is** at `/opt/uploads/`. Always (when the upload persists).
- `terminal` and `execute_code` **do** execute commands in the gateway
  container, which has the `/opt/uploads/` bind mounted read-only.
- "I don't have access to the file" is incorrect unless
  `ls -lt /opt/uploads/` returns zero rows AND
  `docker inspect hermes-stack-hermes-1 | grep uploads` shows no
  `/opt/uploads` mount.

## Failure modes and fallbacks

- **`/opt/uploads/` is empty.** Ask the user to re-upload.
- **`/opt/uploads/` doesn't exist on the filesystem.** The gateway
  compose bind is missing; tell the user this is a deployment-side
  issue (compose change required, then `docker compose up -d hermes`).
- **`ModuleNotFoundError: No module named 'openpyxl'`** — the persistent
  site-packages dir is missing the packages. Reinstall via
  `pip install --target /opt/data/.local/lib/python3.11/site-packages openpyxl 'xlrd<2.0'`
  (see step 2).
- **`.xls` (legacy BIFF) files.** xlrd<2.0 only. xlrd cannot recover
  formula strings from Excel-saved `.xls` files (only cached values
  are retained). The helper emits a per-sheet warning and surfaces
  `formula: null` for every cell. Ask the user to re-save the workbook
  as `.xlsx` in Excel itself before re-running.
- **`.csv`** — handled natively by csv.Sniffer. The engine always
  emits a one-shot "First row treated as header" warning; rows are
  still extracted in their entirety regardless.
- **Large spreadsheets (1M+ cells).** extract.py returns all cells in
  one JSON object. For sub-second response on huge files, ask the user
  if `--mode values` (drop formulas) is sufficient.
- **Merged cells.** Only the anchor (top-left) cell carries the
  value; other cells in the merge are returned with `value: null`.
  Render them as part of the table with `value: null` so the geometry
  of the sheet is preserved.
- **Shared / array formulas.** openpyxl represents the master's text
  via an `ArrayFormula` object. The helper unwraps it to its formula
  text and tags the cell with `formula_type: "array_formula"`. Cells
  covered by the array formula's range (other than the master) are
  emitted with `formula: null` and `value: null` — do not invent
  values for them.
- **Date / datetime cells.** openpyxl returns Python `datetime.datetime`
  or `datetime.date` objects. The helper serialises these as ISO 8601
  strings under both `value` and `value_display` with
  `value_type: "datetime"`. The Excel serial number is **not**
  preserved.
- **Excel error tokens (`#REF!`, `#DIV/0!`, `#NAME?`, `#VALUE!`, …)** —
  openpyxl returns these as ordinary strings starting with `#`. The
  helper surfaces them verbatim under `value`. Render as-is.
- **Password-protected files.** openpyxl refuses to load and exits 1
  with a Python traceback. Ask the user to unlock the file in Excel
  and re-save.
- **Data validation, conditional formatting, charts, pivot tables,
  comments — not extracted.** The helper only walks cell values.
  Mention the gap in the response so the user knows.

## Verification

After running `extract.py`:
- The JSON parses cleanly.
- The sheet the user asked about exists in `sheets`. If not, surface
  the actual sheet names you found and ask the user to disambiguate.
- The cell coordinates you cite in your answer actually contain the
  values/formulas you mentioned.
- If `value` is null for a formula cell, the workbook was last saved
  by openpyxl alone (no Excel recalc); mention this so the user knows
  re-evaluation is needed before trusting the cached values.

## Persistence caveats

- `./hermes-stack install skills --force` rewrites the skill directory
  but does NOT touch the Python packages (they live under
  `/opt/data/.local/`, outside the skill dir). Nothing to recreate after
  a force install.
- The host path `/root/docker/hermes-stack/data/open-webui/uploads/` is
  the source of truth. New uploads land there first, then the bind
  exposes them to the gateway at `/opt/uploads/` (read-only).
- If `/opt/uploads/` is empty inside the gateway but the host path has
  fresh uploads, the gateway hasn't been recreated since the bind was
  added. `cd /root/docker/hermes-stack && docker compose up -d hermes`.
