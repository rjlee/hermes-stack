---
name: ocr-and-documents
description: "Image/photo OCR — read text from a screenshot or photo"
version: 1.0.0
author: Rob
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [OCR, images, screenshots, text-extraction, tesseract]
    category: productivity
    related_skills: [pdf]
---

# Image OCR (tesseract)

Use this when the user sends an image (photo, screenshot, scan) and asks for the
text in it, to "detect/read/extract the text", or to summarise what a picture
says.

The local model has **no vision**: llama.cpp on llm.home serves a text-only
`Qwen3.6-35B-A3B-APEX` GGUF with no `mmproj`, so `vision_analyze` returns
`HTTP 500 - image input is not supported`. Do **not** rely on it. Use the
`tesseract` binary that bootstrap `50-install-ocr.sh` provisions.

## Where the images are

- WhatsApp attachments: `/opt/data/cache/images/img_*.jpg` (newest last)
- Open WebUI uploads: `/opt/uploads/` (read-only)
- The turn's own images are named in the injected `[The user sent an image ...]`
  message — use those exact paths when present.

List them newest-first:

```bash
ls -lt /opt/data/cache/images/ | head
```

## Run OCR

Run this with the **`terminal`** tool (the gateway shell, which has the
`tesseract` binary). Do NOT use `browser_exec`, `execute_code`, or
`vision_analyze` for OCR.

```bash
# single newest image to stdout
f=$(ls -t /opt/data/cache/images/*.jpg | head -1)
tesseract "$f" stdout -l eng 2>/dev/null
```

Always check the binary first and never claim OCR is unavailable without this:

```bash
command -v tesseract || bash /opt/data/.hermes-stack/bootstrap/50-install-ocr.sh
```

Multiple images:

```bash
for f in /opt/data/cache/images/*.jpg; do
  echo "=== $f ==="
  tesseract "$f" stdout -l eng 2>/dev/null
done
```

Tips:
- `--psm 6` assumes a uniform block of text (good for documents); `--psm 3`
  (default) does automatic page segmentation.
- `--psm 0` runs orientation/script detection if a photo is rotated.
- Add languages with `-l eng+deu` — extra language packs are **not** installed
  by default.
- Images are often large phone photos; tesseract handles them directly, but
  pre-scaling with PIL can improve small text.

## Scanned PDFs

`read_file` only reads a PDF's text layer; scanned pages come back with a
`[NEEDS OCR: …]` warning. Render the pages with poppler, then OCR them:

```bash
pdftoppm -jpeg -r 150 -f 1 -l 5 /path/file.pdf /tmp/page
for p in /tmp/page-*.jpg; do
  echo "=== $p ==="
  tesseract "$p" stdout -l eng 2>/dev/null
done
```

For a PDF that already has a text layer, use the fast path instead:

```bash
pdftotext "$pdf" -
```

For tables, forms, merge/split, or metadata use the `pdf` skill (its
`scripts/pdf_read.py` etc. — pypdf/pdfplumber are installed here).

## Install / repair

tesseract is installed by bootstrap `50-install-ocr.sh`. If `tesseract` is
missing (e.g. right after a container recreate, before the bootstrap ran):

```bash
command -v tesseract || bash /opt/data/.hermes-stack/bootstrap/50-install-ocr.sh
```

Do **not** try `apt-get`/`dpkg` directly: the agent runs as uid 10000 `hermes`
with no sudo. The bootstrap uses the hermes SSH key to have the host run apt in
this container as root.

## Do not

- Do not answer image questions from RAG chunks or guessed content.
- Do not call `vision_analyze` (vision is not configured on this deployment).
- Do not use `browser_exec` / Browser Use for OCR — it runs in a separate
  sandbox with no tesseract, and a 2026-09-26 attempt there produced a
  hallucinated "# No Tesseract installed." and no output.
- Do not declare tesseract missing without actually running `command -v tesseract`.
- Do not invent paths like `/mnt/uploads`; the real paths are above.
