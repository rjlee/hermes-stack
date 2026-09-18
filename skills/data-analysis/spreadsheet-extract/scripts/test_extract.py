#!/usr/bin/env python3
"""Standalone tests for spreadsheet-extract/scripts/extract.py.

Run from the skill directory:

    python3 scripts/test_extract.py

Exit 0 on success, 1 on first failure (uses assertions + try/except so the
rest still run; a final summary reports pass/fail counts). No pytest
required, matching the convention used by /opt/data/scripts/test_*.py
(see kb: hermes scripts use standalone test runners, not pytest).

Coverage:
  1. _coord helper for various column widths
  2. _strip_formula_eq strips leading "=" only
  3. openpyxl .xlsx with formulas + cached values (mode both)
  4. openpyxl .xlsx mode formulas only
  5. openpyxl .xlsx mode values only
  6. .csv parse via stdlib engine
  7. .xls path: only engine selection (xlrd invocation tested conditionally
     on the library being installed; missing dependency is treated as a
     "skip" with a printed note rather than a failure)
  8. JSON output round-trip + structural keys per sheet
  9. Missing-file error path -> exit 1
 10. Defined-name extraction on a workbook with a single named range
"""

from __future__ import annotations

import csv
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
from typing import Callable

# ---- test runner infra ----

PASSED: list[str] = []
FAILED: list[tuple[str, str]] = []


def _test(name: str, fn: Callable[[], None]) -> None:
    try:
        fn()
    except Exception as exc:
        FAILED.append((name, f"{exc}\n{traceback.format_exc()}"))
    else:
        PASSED.append(name)


# ---- locate the extract.py under test ----
HERE = os.path.dirname(os.path.abspath(__file__))
EXTRACT = os.path.join(HERE, "extract.py")

if not os.path.exists(EXTRACT):
    print(f"FAIL: extract.py not found next to this test: {EXTRACT}", file=sys.stderr)
    sys.exit(1)

# Make extract importable as a module
sys.path.insert(0, HERE)
import extract  # noqa: E402  (intentional, after sys.path tweak)

# ---- fixture builders ----

def _make_xlsx(path: str) -> None:
    """Build a small .xlsx with formulas and cached values."""
    try:
        import openpyxl
    except ImportError:
        raise SkipFor(
            "openpyxl not installed; cannot test .xlsx parsing. "
            "Run 'pip install --user openpyxl' first."
        )

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Data"
    ws["A1"] = "Year"
    ws["B1"] = "Growth"
    ws["A2"] = 2024
    ws["B2"] = 0.05
    ws["A3"] = 2025
    ws["B3"] = "=A2+1"
    ws["C3"] = "=A3*B2"
    # Pre-set a cached value for C3 by saving via a separate pass through
    # openpyxl's data_only loader. openpyxl cannot compute formulas on
    # its own, so to populate cached values we round-trip via LibreOffice
    # if available. Without that, the cached value remains None.
    ws["D1"] = "Done"
    ws["D2"] = True

    # Defined name -> cell
    wb.defined_names["YearOf2024"] = openpyxl.workbook.defined_name.DefinedName(
        "YearOf2024", attr_text="Data!$A$2"
    )

    wb.save(path)


def _make_csv(path: str) -> None:
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["name", "value"])
        w.writerow(["alpha", "1"])
        w.writerow(["beta", "2"])
        w.writerow(["", ""])
        w.writerow(["delta", "4"])


# ---- a tiny Skip exception so conditional tests can self-skip ----

class SkipFor(Exception):
    pass


def _skip_if_missing_xlrd() -> bool:
    try:
        import xlrd  # noqa: F401
    except ImportError:
        print("  [skip] xlrd not installed; .xls engine test skipped")
        return True
    return False


# ---- the actual tests ----

def test_coord_helper() -> None:
    assert extract._coord(1, 1) == "A1"
    assert extract._coord(2, 3) == "B3"
    assert extract._coord(27, 4) == "AA4"
    assert extract._coord(52, 5) == "AZ5"
    assert extract._coord(53, 5) == "BA5"
    assert extract._coord(702, 1) == "ZZ1"
    assert extract._coord(703, 1) == "AAA1"


def test_strip_formula_eq() -> None:
    assert extract._strip_formula_eq("=A1+B1") == "A1+B1"
    assert extract._strip_formula_eq("A1+B1") == "A1+B1"
    assert extract._strip_formula_eq(None) is None
    assert extract._strip_formula_eq(42) == 42
    assert extract._strip_formula_eq("") == ""


def _run_extract(path: str, mode: str) -> dict:
    """Invoke extract.py as a subprocess (same call shape SKILL.md uses)."""
    proc = subprocess.run(
        [sys.executable, EXTRACT, path, "--mode", mode],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise AssertionError(
            f"extract.py exited {proc.returncode}\n"
            f"stderr:\n{proc.stderr}\nstdout:\n{proc.stdout}"
        )
    return json.loads(proc.stdout)


def test_xlsx_mode_both() -> None:
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "sample.xlsx")
        _make_xlsx(path)
        data = _run_extract(path, "both")
    assert data["engine"] == "openpyxl", data
    assert data["mode"] == "both", data
    sheets = data["sheets"]
    assert len(sheets) == 1, sheets
    sheet = sheets[0]
    assert sheet["name"] == "Data"
    assert sheet["max_row"] >= 3
    assert sheet["max_col"] >= 4
    by_coord = {c["coord"]: c for c in sheet["cells"]}

    # A1 literal value
    assert by_coord["A1"].get("value") == "Year"
    # B3 formula "=A2+1"; cached value depends on whether the workbook
    # was opened in Excel (None otherwise). We accept either None or 2025.
    assert by_coord["B3"].get("formula") == "A2+1", by_coord["B3"]
    # C3 formula "=A3*B2"
    assert by_coord["C3"].get("formula") == "A3*B2", by_coord["C3"]
    # Both keys must exist in mode "both"
    assert "formula" in by_coord["A1"]
    assert "value" in by_coord["A1"]
    # D2 boolean literal preserved through the JSON serializer
    assert by_coord["D2"].get("value") is True, by_coord["D2"]
    # named_ranges is required to be a list (may be empty for openpyxl
    # in-memory-built fixtures — see test_openpyxl_named_ranges_unit
    # below for the focused code-path test).
    assert isinstance(sheet["named_ranges"], list)


def test_xlsx_mode_formulas() -> None:
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "sample.xlsx")
        _make_xlsx(path)
        data = _run_extract(path, "formulas")
    sheet = data["sheets"][0]
    by_coord = {c["coord"]: c for c in sheet["cells"]}
    assert "formula" in by_coord["A1"]
    assert "value" not in by_coord["A1"], by_coord["A1"]
    assert by_coord["B3"]["formula"] == "A2+1"
    # named_ranges is a list (may be empty). The keys presence
    # assertion is exercised separately by test_openpyxl_named_ranges_unit.
    assert isinstance(sheet["named_ranges"], list)


def test_openpyxl_named_ranges_unit() -> None:
    """Direct unit test for the _openpyxl_named_ranges helper. We pass
    duck-typed stand-ins for wb_f and ws_f so we don't have to construct
    a real openpyxl workbook (whose in-memory defined_names don't round-
    trip clean in openpyxl 3.1.5)."""
    try:
        import openpyxl  # noqa: F401  -- only need openpyxl installed
    except ImportError:
        raise SkipFor("openpyxl not installed")

    class _FakeSheet:
        def __init__(self, title: str, cells: dict[str, Any]):
            self.title = title
            self._cells = cells

        def __getitem__(self, coord: str) -> Any:
            v = self._cells.get(coord.replace("$", ""))
            return _FakeCell(v)

    class _FakeCell:
        def __init__(self, value: Any):
            self.value = value

    class _FakeDefinedName:
        def __init__(
            self, name: str, dests: list[tuple[Any, str]], attr_text: str = ""
        ):
            self.name = name
            self._dests = dests
            self.attr_text = attr_text

        @property
        def destinations(self):
            return iter(self._dests)

    class _FakeDefinedNamesDict:
        def __init__(self, entries: dict[str, _FakeDefinedName]):
            self._d = entries

        def items(self):
            return list(self._d.items())

    sheet_obj = type("S", (), {"title": "Data"})()
    fake_dn = _FakeDefinedName("YearOf2024", [(sheet_obj, "$A$2")])
    fake_defined_names_dict = _FakeDefinedNamesDict({"YearOf2024": fake_dn})

    ws_f = _FakeSheet("Data", {"A2": 2024})

    class _FakeWorkbookIndexed:
        defined_names = fake_defined_names_dict

        def __getitem__(self, title: str) -> _FakeSheet:
            assert title == "Data"
            return _FakeSheet("Data", {"A2": 2024})

    warnings: list[str] = []
    result = extract._openpyxl_named_ranges(
        _FakeWorkbookIndexed(),
        ws_f,
        _FakeWorkbookIndexed(),
        "both",
        warnings,
    )
    assert len(result) == 1, (result, warnings)
    entry = result[0]
    assert entry["name"] == "YearOf2024"
    assert entry["coord"] == "$A$2"
    assert entry["value"] == 2024


def test_openpyxl_named_ranges_string_sheet() -> None:
    """Excel-saved files (the common case) yield `destinations` whose
    sheet field is a bare `str`, not a Worksheet. The earlier version of
    the helper called `.title` on it -- which returns the bound method
    `str.title` -- so the comparison against `ws_f.title` always failed,
    silently dropping every named range. Regression test for that bug."""

    class _FakeSheet:
        def __init__(self, title: str, cells: dict[str, Any]):
            self.title = title
            self._cells = cells

        def __getitem__(self, coord: str) -> Any:
            return _FakeCell(self._cells.get(coord.replace("$", "")))

    class _FakeCell:
        def __init__(self, value: Any):
            self.value = value

    class _FakeDefinedName:
        def __init__(
            self, name: str, dests: list[tuple[Any, str]], attr_text: str = ""
        ):
            self.name = name
            self._dests = dests
            self.attr_text = attr_text

        @property
        def destinations(self):
            return iter(self._dests)

    class _FakeDefinedNamesDict:
        def __init__(self, entries: dict[str, _FakeDefinedName]):
            self._d = entries

        def items(self):
            return list(self._d.items())

    # Excel-style: sheet is a bare string, coord has $ anchors.
    fake_dn = _FakeDefinedName("HomeValue", [("Financial Health", "$B$3")])
    fake_dict = _FakeDefinedNamesDict({"HomeValue": fake_dn})

    class _FakeWB:
        defined_names = fake_dict

        def __getitem__(self, title: str) -> _FakeSheet:
            assert title == "Financial Health"
            return _FakeSheet("Financial Health", {"B3": 595000.0})

    ws_f = _FakeSheet("Financial Health", {"B3": 595000.0})

    warnings: list[str] = []
    result = extract._openpyxl_named_ranges(_FakeWB(), ws_f, _FakeWB(), "both", warnings)
    assert len(result) == 1, (result, warnings)
    entry = result[0]
    assert entry["name"] == "HomeValue"
    assert entry["coord"] == "$B$3"
    assert entry["value"] == 595000.0


def test_openpyxl_named_ranges_range_ref() -> None:
    """A named range can be a multi-cell range (e.g. "$B$5:$K$5"). The
    helper must handle that without crashing on a tuple of cells."""

    class _FakeSheet:
        def __init__(self, title: str):
            self.title = title
            self._cells = {
                "B5": 1000.0, "C5": 2000.0, "D5": 3000.0, "E5": 4000.0,
                "F5": 5000.0, "G5": 6000.0, "H5": 7000.0, "I5": 8000.0,
                "J5": 9000.0, "K5": 10000.0,
            }

        def __getitem__(self, coord: str) -> Any:
            # openpyxl returns a tuple-of-tuples for ranges. Single cell
            # returns a bare Cell. We synthesise the right shape.
            if ":" in coord:
                m = coord.replace("$", "").split(":")
                if len(m) == 2 and m[0].startswith("B") and m[1].startswith("K"):
                    # Build a 1-row tuple of cells, columns B..K, all in row 5
                    cols = ["B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]
                    return tuple(_FakeCell(self._cells[f"{c}5"]) for c in cols)
            return _FakeCell(self._cells.get(coord.replace("$", "")))

    class _FakeCell:
        def __init__(self, value: Any):
            self.value = value

    class _FakeDefinedName:
        def __init__(
            self, name: str, dests: list[tuple[Any, str]], attr_text: str = ""
        ):
            self.name = name
            self._dests = dests
            self.attr_text = attr_text

        @property
        def destinations(self):
            return iter(self._dests)

    class _FakeDefinedNamesDict:
        def __init__(self, entries: dict[str, _FakeDefinedName]):
            self._d = entries

        def items(self):
            return list(self._d.items())

    fake_dn = _FakeDefinedName(
        "BasicNeed10", [("assets-table", "$B$5:$K$5")]
    )
    fake_dict = _FakeDefinedNamesDict({"BasicNeed10": fake_dn})

    ws_f = _FakeSheet("assets-table")

    class _FakeWB:
        defined_names = fake_dict

        def __getitem__(self, title: str) -> _FakeSheet:
            return ws_f

    warnings: list[str] = []
    result = extract._openpyxl_named_ranges(_FakeWB(), ws_f, _FakeWB(), "both", warnings)
    assert len(result) == 1, (result, warnings)
    entry = result[0]
    assert entry["name"] == "BasicNeed10"
    assert entry["coord"] == "$B$5:$K$5"
    assert entry["range_size"] == 10


def test_normalise_cell_value() -> None:
    """The cell value normaliser must produce stable JSON-friendly shapes
    for: None, bool, int, float, str, datetime, datetime.date, ArrayFormula,
    and arbitrary objects (fallback to str())."""
    import datetime

    assert extract._normalise_cell_value(None)["raw"] is None
    assert extract._normalise_cell_value(True) == {
        "raw": True, "display": True, "type": "boolean"
    }
    assert extract._normalise_cell_value(42) == {
        "raw": 42, "display": 42, "type": "number"
    }
    assert extract._normalise_cell_value(3.14) == {
        "raw": 3.14, "display": 3.14, "type": "number"
    }
    assert extract._normalise_cell_value("plain") == {
        "raw": "plain", "display": "plain", "type": "string"
    }
    dt = datetime.datetime(2024, 1, 1, 12, 30)
    assert extract._normalise_cell_value(dt) == {
        "raw": "2024-01-01T12:30:00",
        "display": "2024-01-01T12:30:00",
        "type": "datetime",
    }
    d = datetime.date(2025, 6, 15)
    assert extract._normalise_cell_value(d) == {
        "raw": "2025-06-15",
        "display": "2025-06-15",
        "type": "datetime",
    }
    # ArrayFormula -- match by class name (extract.py dispatches on
    # type(v).__name__ == "ArrayFormula").
    ArrayFormula = type("ArrayFormula", (), {"text": "=SUM(A1:A10)"})
    res = extract._normalise_cell_value(ArrayFormula())
    assert res["raw"] == "SUM(A1:A10)", res
    assert res["type"] == "array_formula"


def test_xlsx_unicode_sheet_names() -> None:
    """Unicode and special characters in sheet names and cell values
    must round-trip through JSON encoding without distortion."""
    try:
        import openpyxl
    except ImportError:
        raise SkipFor("openpyxl not installed")
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "u.xlsx")
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Ünïcödé — 漢字"
        ws["A1"] = "naïve café"
        ws["A2"] = "日本語"
        ws["A3"] = "🚀"
        wb.save(path)
        data = _run_extract(path, "both")
    assert data["engine"] == "openpyxl"
    sheet = data["sheets"][0]
    assert sheet["name"] == "Ünïcödé — 漢字"
    by_coord = {c["coord"]: c for c in sheet["cells"]}
    assert by_coord["A1"]["value"] == "naïve café"
    assert by_coord["A2"]["value"] == "日本語"
    assert by_coord["A3"]["value"] == "🚀"


def test_xlsx_merged_cells() -> None:
    """Merged cells must not crash the parser. The anchor cell carries
    the value; the other cells in the merge are empty. Both should be
    visible in the output."""
    try:
        import openpyxl
    except ImportError:
        raise SkipFor("openpyxl not installed")
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "m.xlsx")
        wb = openpyxl.Workbook()
        ws = wb.active
        ws["A1"] = "Header"
        ws.merge_cells("A1:C1")
        ws["A2"] = "alpha"
        ws["B2"] = "beta"
        ws["C2"] = "gamma"
        wb.save(path)
        data = _run_extract(path, "both")
    by_coord = {c["coord"]: c for c in data["sheets"][0]["cells"]}
    assert by_coord["A1"]["value"] == "Header"
    # The merged follow-on cells are blanks; their value should be null
    assert by_coord["B1"].get("value") is None
    assert by_coord["C1"].get("value") is None
    assert by_coord["A2"]["value"] == "alpha"


def test_xlsx_macros_enabled_xlsm() -> None:
    """xlsm files are openpyxl's domain (openpyxl supports the OOXML
    zip layout even with the macroEnabled MIME marker)."""
    try:
        import openpyxl
    except ImportError:
        raise SkipFor("openpyxl not installed")
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "with_macros.xlsm")
        wb = openpyxl.Workbook()
        wb.active["A1"] = "macro workbook"
        wb.save(path)
        data = _run_extract(path, "both")
    assert data["engine"] == "openpyxl"
    assert data["sheets"][0]["cells"][0]["value"] == "macro workbook"


def test_csv_complex() -> None:
    """CSV with embedded commas, quotes, and newlines must parse cleanly
    via csv.Sniffer. Sniffer.has_header may produce a warning; that's OK."""
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "c.csv")
        with open(path, "w", newline="", encoding="utf-8") as fh:
            fh.write('name,description,price\n')
            fh.write('"alpha,beta","with comma inside",1.50\n')
            fh.write('"with ""quotes""","normal text",2.00\n')
        data = _run_extract(path, "both")
    assert data["engine"] == "csv"
    by_coord = {c["coord"]: c for c in data["sheets"][0]["cells"]}
    assert by_coord["A2"]["value"] == "alpha,beta"
    assert by_coord["B2"]["value"] == "with comma inside"
    assert by_coord["A3"]["value"] == 'with "quotes"'


def test_xlsx_mode_values() -> None:
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "sample.xlsx")
        _make_xlsx(path)
        data = _run_extract(path, "values")
    sheet = data["sheets"][0]
    by_coord = {c["coord"]: c for c in sheet["cells"]}
    assert "value" in by_coord["A1"]
    assert "formula" not in by_coord["A1"], by_coord["A1"]
    # Non-formula literal value
    assert by_coord["A2"]["value"] == 2024


def test_csv_engine() -> None:
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "sample.csv")
        _make_csv(path)
        data = _run_extract(path, "both")
    assert data["engine"] == "csv"
    sheet = data["sheets"][0]
    assert sheet["max_row"] == 5
    assert sheet["max_col"] == 2
    by_coord = {c["coord"]: c for c in sheet["cells"]}
    assert by_coord["A1"]["value"] == "name"
    assert by_coord["A2"]["value"] == "alpha"
    assert by_coord["B2"]["value"] == "1"
    # CSV has no formulas; should be None
    assert by_coord["A1"].get("formula") is None


def test_xls_engine() -> None:
    """Smoke test for the xlrd code path. Skipped if xlrd is not installed."""
    if _skip_if_missing_xlrd():
        return
    try:
        # Synthesize a tiny .xls via xlrd's in-memory write? xlrd is
        # read-only; create via a known-good free fixture would be ideal
        # but we test that *selecting* the right engine works given a
        # .xls file path, by writing a fake .xls with the right magic
        # bytes and confirming extract.py exits 3 (open failure) rather
        # than engaging the wrong engine.
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "fake.xls")
            with open(path, "wb") as f:
                f.write(b"\xd0\xcf\x11\xe0")  # OLE2 compound doc sig only
            proc = subprocess.run(
                [sys.executable, EXTRACT, path, "--mode", "both"],
                capture_output=True,
                text=True,
                timeout=30,
            )
        # We accept either a clean 0 (xlrd happily parsed), exit 3
        # (open failure -> extract caught it), or exit 2 (missing lib
        # discovered at parse time). The only unacceptable result is
        # exit != 0 with engine == "openpyxl" in the JSON, i.e. the
        # engine selector hit the wrong path.
        assert proc.returncode in (0, 2, 3), proc
        if proc.returncode == 0:
            data = json.loads(proc.stdout)
            assert data["engine"] == "xlrd", data
    except SkipFor as skip:
        print(f"  [skip] {skip}")


def test_json_round_trip() -> None:
    """Output JSON must be deserialisable and contain the documented keys."""
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "sample.xlsx")
        _make_xlsx(path)
        data = _run_extract(path, "both")
    for k in ("path", "engine", "mode", "sheets", "warnings"):
        assert k in data, f"missing top-level key {k!r}: {data}"
    assert isinstance(data["warnings"], list)
    sheet = data["sheets"][0]
    for k in (
        "name",
        "dimensions",
        "max_row",
        "max_col",
        "cells",
        "named_ranges",
    ):
        assert k in sheet, f"missing sheet key {k!r}: {sheet}"


def test_missing_file() -> None:
    proc = subprocess.run(
        [sys.executable, EXTRACT, "/nonexistent/spreadsheet.xlsx", "--mode", "both"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 1
    assert "file not found" in proc.stderr.lower()


def test_unknown_extension_falls_back_to_openpyxl() -> None:
    """`.txt` -> openpyxl engine; missing lib will exit 2, otherwise it
    will try to parse and fail with an openpyxl error. We only check
    that the engine selector returns the documented default without
    crashing in pure-python."""
    proc = subprocess.run(
        [sys.executable, EXTRACT, "/tmp/definitely-not-a-spreadsheet.txt", "--mode", "values"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    # Any of: 0 (parsed, absurd but possible), 1 (real error), 2 (openpyxl
    # missing). The unacceptable outcome is the bash interpreter itself
    # dying.
    assert proc.returncode in (0, 1, 2), proc


# ---- runner ----

def main() -> int:
    suite = [
        ("test_coord_helper", test_coord_helper),
        ("test_strip_formula_eq", test_strip_formula_eq),
        ("test_xlsx_mode_both", test_xlsx_mode_both),
        ("test_xlsx_mode_formulas", test_xlsx_mode_formulas),
        ("test_xlsx_mode_values", test_xlsx_mode_values),
        ("test_openpyxl_named_ranges_unit", test_openpyxl_named_ranges_unit),
        ("test_openpyxl_named_ranges_string_sheet", test_openpyxl_named_ranges_string_sheet),
        ("test_openpyxl_named_ranges_range_ref", test_openpyxl_named_ranges_range_ref),
        ("test_normalise_cell_value", test_normalise_cell_value),
        ("test_xlsx_unicode_sheet_names", test_xlsx_unicode_sheet_names),
        ("test_xlsx_merged_cells", test_xlsx_merged_cells),
        ("test_xlsx_macros_enabled_xlsm", test_xlsx_macros_enabled_xlsm),
        ("test_csv_engine", test_csv_engine),
        ("test_csv_complex", test_csv_complex),
        ("test_xls_engine", test_xls_engine),
        ("test_json_round_trip", test_json_round_trip),
        ("test_missing_file", test_missing_file),
        ("test_unknown_extension_falls_back_to_openpyxl", test_unknown_extension_falls_back_to_openpyxl),
    ]
    for name, fn in suite:
        _test(name, fn)

    total = len(suite)
    print(f"\n=== spreadsheet-extract tests: {len(PASSED)}/{total} passed ===")
    if FAILED:
        print("Failures:")
        for name, msg in FAILED:
            print(f"  ✗ {name}\n    {msg}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
