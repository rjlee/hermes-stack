#!/usr/bin/env python3
"""Extract formulas and values from a spreadsheet.

Reads .xlsx/.xlsm (openpyxl), .xls (xlrd<2.0), or .csv (stdlib) and emits
a single JSON object to stdout:

    {
      "path": "...",
      "engine": "openpyxl|xlrd|csv",
      "mode": "formulas|values|both",
      "sheets": [
        {
          "name": "Sheet1",
          "dimensions": [max_row, max_col],
          "max_row": int,
          "max_col": int,
          "cells": [
            {"coord": "A1", "formula": null|"=...", "value": ...},
            ...
          ],
          "named_ranges": [
            {"name": "...", "coord": "...", "formula": ..., "value": ...},
            ...
          ]
        }
      ],
      "warnings": ["..."]
    }

Per-sheet cell iteration is over the tight bounding box (max_row x max_col).
For openpyxl modes formulas and both, the cell .value returned when
data_only=False is the literal formula string (or literal value for
non-formula cells). data_only=True yields the last cached computed value.
The same cell coordinates are walked twice (formula pass + value pass) and
the output merged per coord so a downstream renderer can show formula and
cached value side by side.

Usage:
    extract.py PATH [--mode {formulas,values,both}]

Exits 0 on success, 2 on a missing dependency with a helpful message,
3 on file-format errors, 1 on any other error. Warnings are non-fatal and
appear in the `warnings` array.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import traceback
from typing import Any, Iterable


# ---------- json helpers ----------

def _json_default(obj: Any) -> Any:
    """Best-effort serialiser for cell values that aren't JSON-native."""
    if obj is None:
        return None
    try:
        return float(obj)
    except (TypeError, ValueError):
        pass
    try:
        return str(obj)
    except Exception:
        return repr(obj)


def _emit(payload: dict) -> None:
    json.dump(payload, sys.stdout, default=_json_default, ensure_ascii=False)
    sys.stdout.write("\n")


# ---------- helpers ----------

def _coord(col: int, row: int) -> str:
    """1-indexed (col, row) -> A1, B3, AA10, ... Honors Excel column letters."""
    letters = ""
    n = col
    while n > 0:
        n, rem = divmod(n - 1, 26)
        letters = chr(ord("A") + rem) + letters
    return f"{letters}{row}"


def _strip_formula_eq(formula: Any) -> Any:
    """openpyxl returns formula strings with leading '='. Drop it for clean
    downstream rendering; keep raw otherwise."""
    if isinstance(formula, str) and formula.startswith("="):
        return formula[1:]
    return formula


def _normalise_cell_value(v: Any) -> dict[str, Any]:
    """Return a JSON-friendly representation of an openpyxl cell value.

    openpyxl uses a few return types that don't serialise cleanly with a
    naive json.dump:
      * `datetime.datetime` / `datetime.date` for date-formatted cells
      * `ArrayFormula` for cells governed by a single shared array formula
      * `openpyxl.cell.rich_text.CellRichText` for in-cell rich text
      * `bool` is a subclass of int (so it must be tested FIRST)
      * strings beginning with '=' are formulas (kept as the literal
        string by openpyxl when data_only=False)
    Returns a dict {"raw": ..., "display": str} so callers can present
    either or both. display is the user-facing rendering; raw is the
    structured representation suitable for downstream processing.
    """
    if v is None:
        return {"raw": None, "display": None}

    # bool is an int subclass — check first.
    if isinstance(v, bool):
        return {"raw": v, "display": v, "type": "boolean"}

    if isinstance(v, (int, float)):
        return {"raw": v, "display": v, "type": "number"}

    if isinstance(v, str):
        return {"raw": v, "display": v, "type": "string"}

    # Excel errors come back as the string the cell currently shows,
    # e.g. "#REF!", "#DIV/0!". openpyxl tags them with data_type == "e"
    # but the .value is already the string. Treat as a string.

    try:
        import datetime
    except ImportError:
        datetime = None  # type: ignore
    if datetime is not None and isinstance(v, (datetime.datetime, datetime.date)):
        return {
            "raw": v.isoformat(),
            "display": v.isoformat(),
            "type": "datetime",
        }

    # ArrayFormula — unwrap to its stored text. The cell containing the
    # master is a single shared formula that affects every cell in its
    # range; the helper emits the master's text and we leave the
    # downstream renderer aware that the same formula applies to all
    # cells in the range. The openpyxl ArrayFormula class exposes the
    # formula text under several attributes depending on version; try
    # them in order.
    mod = type(v).__module__
    cls = type(v).__name__
    if cls == "ArrayFormula":
        for attr in ("text", "formula", "ref", "value"):
            text = getattr(v, attr, None)
            if isinstance(text, str) and text:
                # Strip a leading "=" if present for visual symmetry
                # with the formula pass on regular cells.
                if text.startswith("="):
                    text = text[1:]
                return {
                    "raw": text,
                    "display": text,
                    "type": "array_formula",
                }
        return {
            "raw": None,
            "display": str(v),
            "type": "array_formula",
        }

    if cls == "CellRichText" or mod.endswith("rich_text"):
        return {
            "raw": str(v),
            "display": str(v),
            "type": "rich_text",
        }

    # Fallback: stringify.
    return {"raw": repr(v), "display": str(v), "type": cls.lower()}


# ---------- engine: openpyxl (.xlsx / .xlsm) ----------

def _parse_openpyxl(path: str, mode: str, warnings: list[str]) -> list[dict]:
    try:
        import openpyxl
    except ImportError:
        sys.stderr.write(
            "ERROR: openpyxl is required for .xlsx/.xlsm. "
            "Install it: pip install --user openpyxl\n"
        )
        sys.exit(2)

    wb_f = openpyxl.load_workbook(path, data_only=False)
    wb_v = (
        openpyxl.load_workbook(path, data_only=True)
        if mode in ("values", "both")
        else None
    )

    sheets: list[dict] = []
    for ws_f in wb_f.worksheets:
        ws_v = wb_v[ws_f.title] if wb_v is not None else None

        max_row = ws_f.max_row or 0
        max_col = ws_f.max_column or 0
        cells = []
        for row in range(1, max_row + 1):
            for col in range(1, max_col + 1):
                c_f = ws_f.cell(row=row, column=col)
                c_v = ws_v.cell(row=row, column=col) if ws_v is not None else None
                entry: dict[str, Any] = {"coord": _coord(col, row)}
                if mode in ("formulas", "both"):
                    v_f = c_f.value
                    # If data_only=False returns a non-string, that's a
                    # literal value (number, bool, datetime). Surface as-is.
                    if v_f is None:
                        entry["formula"] = None
                    elif isinstance(v_f, str) and v_f.startswith("="):
                        entry["formula"] = _strip_formula_eq(v_f)
                    else:
                        # treat as a literal value: don't surface it under
                        # "formula"; store raw + display via the normaliser
                        # for shape stability.
                        normalised = _normalise_cell_value(v_f)
                        entry["formula"] = normalised["raw"]
                        entry["formula_display"] = normalised["display"]
                        entry["formula_type"] = normalised.get("type", "literal")
                if mode in ("values", "both"):
                    v_v = c_v.value if c_v is not None else None
                    normalised = _normalise_cell_value(v_v)
                    entry["value"] = normalised["raw"]
                    entry["value_display"] = normalised["display"]
                    entry["value_type"] = normalised.get("type", "unknown")
                cells.append(entry)

        named_ranges = _openpyxl_named_ranges(wb_f, ws_f, wb_v, mode, warnings)

        sheets.append(
            {
                "name": ws_f.title,
                "dimensions": [max_row, max_col],
                "max_row": max_row,
                "max_col": max_col,
                "cells": cells,
                "named_ranges": named_ranges,
            }
        )
    return sheets


def _openpyxl_named_ranges(
    wb_f: Any, ws_f: Any, wb_v: Any, mode: str, warnings: list[str]
) -> list[dict]:
    """Enumerate defined names scoped to the workbook; report per-sheet by
    intersecting the named range's destination(s) with the sheet's bounds."""
    out: list[dict] = []
    try:
        defn = wb_f.defined_names
    except Exception as exc:
        warnings.append(f"defined_names enumeration failed: {exc}")
        return out

    try:
        items = list(defn.items())
    except Exception as exc:
        warnings.append(f"defined_names iteration failed: {exc}")
        return out

    for name_str, dn in items:
        try:
            destinations = list(dn.destinations)
        except Exception as exc:
            warnings.append(
                f"named range {name_str!r} destinations lookup failed: {exc}"
            )
            continue

        if not destinations:
            # Fall back to attr_text when destinations came back empty
            # (openpyxl in-memory saves can lose destinations; Excel-saved
            # files always have them). attr_text is the workbook-scope
            # definition; if it references this sheet with an explicit
            # prefix (e.g. "Sheet1!$A$2"), we surface it as a single entry.
            attr_text = getattr(dn, "attr_text", None) or ""
            if "!" not in attr_text:
                continue
            sheet_name, _, coord = attr_text.partition("!")
            coord = coord.replace("$", "").strip()
            if sheet_name.strip("'") != ws_f.title:
                continue
            destinations = [(ws_f.title, coord)]
            warnings.append(
                f"named range {name_str!r}: destinations were empty; "
                f"fell back to attr_text {attr_text!r}"
            )

        for sheet_obj, coord in destinations:
            # openpyxl's destinations yields (sheet, coord) tuples where
            # `sheet` is either a Worksheet instance (created from an
            # in-memory DefinedName) or a bare string (read from an Excel-
            # saved file). Both have a `.title` attribute -- for Worksheets
            # it's a plain string attribute, for `str` it's the built-in
            # `str.title` method. Normalise to a plain string.
            if isinstance(sheet_obj, str):
                sheet_title = sheet_obj
            else:
                title_attr = getattr(sheet_obj, "title", None)
                if isinstance(title_attr, str):
                    sheet_title = title_attr
                else:
                    sheet_title = str(sheet_obj)
            if sheet_title != ws_f.title:
                continue
            # If coord is a range (e.g. "$B$5:$K$5"), ws_f[coord] returns
            # a tuple of Cell objects; just record the range reference and
            # surface each cell inside it under one named-range entry.
            if ":" in coord:
                try:
                    cells_in_range = ws_f[coord]
                except Exception as exc:
                    warnings.append(
                        f"named range {name_str!r} -> range {coord} not "
                        f"resolvable: {exc}"
                    )
                    continue
                # Flatten the (possibly 2D) tuple of cells
                flat = []
                if isinstance(cells_in_range, tuple):
                    for row in cells_in_range:
                        if isinstance(row, tuple):
                            flat.extend(row)
                        else:
                            flat.append(row)
                else:
                    flat = [cells_in_range]
                if not flat:
                    continue
                first = flat[0]
                entry: dict[str, Any] = {
                    "name": name_str,
                    "coord": coord,
                    "range_size": len(flat),
                }
                if mode in ("formulas", "both"):
                    entry["formula"] = _normalise_cell_value(first.value)["raw"]
                if mode in ("values", "both"):
                    try:
                        cell_v = wb_v[sheet_title][coord] if wb_v is not None else None
                        first_v = cell_v[0][0] if (
                            isinstance(cell_v, tuple)
                            and cell_v
                            and isinstance(cell_v[0], tuple)
                            and cell_v[0]
                        ) else (
                            cell_v if not isinstance(cell_v, tuple) else None
                        )
                        normalised = _normalise_cell_value(
                            getattr(first_v, "value", first_v)
                            if first_v is not None else None
                        )
                        entry["value"] = normalised["raw"]
                        entry["value_display"] = normalised["display"]
                        entry["value_type"] = normalised.get("type", "unknown")
                    except Exception:
                        entry["value"] = None
                out.append(entry)
                continue

            try:
                cell_f = ws_f[coord]
            except Exception as exc:
                warnings.append(
                    f"named range {name_str!r} -> {coord} not resolvable: {exc}"
                )
                continue
            entry: dict[str, Any] = {
                "name": name_str,
                "coord": coord,
            }
            if mode in ("formulas", "both"):
                entry["formula"] = _normalise_cell_value(cell_f.value)["raw"]
            if mode in ("values", "both"):
                try:
                    cell_v = wb_v[sheet_title][coord] if wb_v is not None else None
                    if isinstance(cell_v, tuple):
                        v_obj = (
                            cell_v[0][0]
                            if cell_v and isinstance(cell_v[0], tuple) and cell_v[0]
                            else None
                        )
                        raw = getattr(v_obj, "value", v_obj) if v_obj is not None else None
                    elif cell_v is not None:
                        raw = cell_v.value
                    else:
                        raw = None
                    normalised = _normalise_cell_value(raw)
                    entry["value"] = normalised["raw"]
                    entry["value_display"] = normalised["display"]
                    entry["value_type"] = normalised.get("type", "unknown")
                except Exception:
                    entry["value"] = None
            out.append(entry)
    return out


# ---------- engine: xlrd (.xls) ----------

def _parse_xlrd(path: str, mode: str, warnings: list[str]) -> list[dict]:
    try:
        import xlrd
    except ImportError:
        sys.stderr.write(
            "ERROR: xlrd<2.0 is required for legacy .xls. Install it: "
            "pip install --user 'xlrd<2.0'\n"
        )
        sys.exit(2)

    try:
        book = xlrd.open_workbook(path, formatting_info=False)
    except Exception as exc:
        sys.stderr.write(f"ERROR: xlrd could not open {path}: {exc}\n")
        sys.exit(3)

    sheets: list[dict] = []
    for sheet in book.sheets():
        max_row = sheet.nrows
        max_col = sheet.ncols
        cells = []
        emitted_formula_warning = False
        for r in range(max_row):
            for c in range(max_col):
                v = sheet.cell_value(r, c)
                ctype = sheet.cell_type(r, c) if hasattr(sheet, "cell_type") else 0
                entry: dict[str, Any] = {"coord": _coord(c + 1, r + 1)}
                if mode in ("formulas", "both"):
                    # xlrd does not retain formula strings after the
                    # spreadsheet is saved by Excel (only the cached value
                    # is kept). Surface a single-sheet warning instead of
                    # one per cell.
                    if not emitted_formula_warning:
                        warnings.append(
                            f"sheet '{sheet.name}': xlrd returns cached "
                            f"values only (no formula strings); for "
                            f"formulas, save the workbook as .xlsx and re-run."
                        )
                        emitted_formula_warning = True
                    entry["formula"] = None
                if mode in ("values", "both"):
                    normalised = _normalise_cell_value(v if v != "" else None)
                    entry["value"] = normalised["raw"]
                    entry["value_display"] = normalised["display"]
                    entry["value_type"] = normalised.get("type", "unknown")
                cells.append(entry)

        named_ranges: list[dict] = []
        if hasattr(book, "name_obj_list"):
            for nobj in book.name_obj_list:
                try:
                    if nobj.scope != -1 and nobj.scope != sheet.name:
                        continue
                    coord_text = (
                        f"{nobj.formula_text}"
                        if hasattr(nobj, "formula_text")
                        else ""
                    )
                    if not coord_text:
                        continue
                    entry = {"name": nobj.name, "coord": coord_text}
                    if mode in ("formulas", "both"):
                        entry["formula"] = None
                    if mode in ("values", "both"):
                        entry["value"] = None
                    named_ranges.append(entry)
                except Exception as exc:
                    warnings.append(
                        f"named range {nobj.name!r} skipped: {exc}"
                    )

        sheets.append(
            {
                "name": sheet.name,
                "dimensions": [max_row, max_col],
                "max_row": max_row,
                "max_col": max_col,
                "cells": cells,
                "named_ranges": named_ranges,
            }
        )
    return sheets


# ---------- engine: csv ----------

def _parse_csv(path: str, mode: str, warnings: list[str]) -> list[dict]:
    # CSV does not have formulas; "formula" is always None and "value"
    # carries the literal cell contents. Modes formulas/both collapse to
    # the same output (formulas are N/A).
    rows: list[list[str]] = []
    with open(path, "r", newline="", encoding="utf-8", errors="replace") as fh:
        sample = fh.read(8192)
        fh.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample)
        except csv.Error:
            dialect = csv.excel
        try:
            has_header = csv.Sniffer().has_header(sample)
        except csv.Error:
            has_header = True
        if has_header:
            warnings.append(
                "First row treated as header (csv.Sniffer.has_header=True); "
                "extracted into rows anyway for completeness."
            )
        reader = csv.reader(fh, dialect)
        for row in reader:
            rows.append(row)

    max_row = len(rows)
    max_col = max((len(r) for r in rows), default=0)
    cells = []
    for r_idx, row in enumerate(rows, start=1):
        for c_idx in range(1, max_col + 1):
            v = row[c_idx - 1] if c_idx - 1 < len(row) else None
            entry: dict[str, Any] = {"coord": _coord(c_idx, r_idx)}
            if mode in ("formulas", "both"):
                entry["formula"] = None
            if mode in ("values", "both"):
                normalised = _normalise_cell_value(v)
                entry["value"] = normalised["raw"]
                entry["value_display"] = normalised["display"]
                entry["value_type"] = normalised.get("type", "string")
            cells.append(entry)

    return [
        {
            "name": os.path.basename(path),
            "dimensions": [max_row, max_col],
            "max_row": max_row,
            "max_col": max_col,
            "cells": cells,
            "named_ranges": [],
        }
    ]


# ---------- entry point ----------

def _detect_engine(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext in (".xlsx", ".xlsm"):
        return "openpyxl"
    if ext == ".xls":
        return "xlrd"
    if ext == ".csv":
        return "csv"
    return "openpyxl"


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Extract formulas + values from a spreadsheet."
    )
    parser.add_argument("path", help="Path to the spreadsheet file.")
    parser.add_argument(
        "--mode",
        choices=("formulas", "values", "both"),
        default="both",
        help="What to emit per cell. Default: both.",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    if not os.path.exists(args.path):
        sys.stderr.write(f"ERROR: file not found: {args.path}\n")
        return 1

    engine = _detect_engine(args.path)
    warnings: list[str] = []
    try:
        if engine == "openpyxl":
            sheets = _parse_openpyxl(args.path, args.mode, warnings)
        elif engine == "xlrd":
            sheets = _parse_xlrd(args.path, args.mode, warnings)
        elif engine == "csv":
            sheets = _parse_csv(args.path, args.mode, warnings)
        else:
            sys.stderr.write(f"ERROR: unknown engine {engine!r}\n")
            return 1
    except SystemExit:
        raise
    except Exception:
        sys.stderr.write(
            "ERROR: unexpected failure parsing "
            f"{args.path}:\n{traceback.format_exc()}"
        )
        return 1

    _emit(
        {
            "path": os.path.abspath(args.path),
            "engine": engine,
            "mode": args.mode,
            "sheets": sheets,
            "warnings": warnings,
        }
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
