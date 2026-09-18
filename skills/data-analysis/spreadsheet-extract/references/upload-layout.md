# Open WebUI upload layout

This document is a reference for the `spreadsheet-extract` skill. It records
the on-disk path convention used by Open WebUI when a chat attachment is
uploaded, so the skill body does not need to re-derive it every time.

## Path pattern

Open WebUI (`ghcr.io/open-webui/open-webui`) writes every uploaded file to a
single flat directory:

    <DATA_DIR>/uploads/<uuid4>_<safe_original_filename>

`<DATA_DIR>` in this deployment is `/app/backend/data` inside the Open WebUI
container, bind-mounted to `/root/docker/hermes-stack/data/open-webui/` on
the host. See `docker-compose.yml` for the exact bind.

`<uuid4>` is a standard UUID4 identifier that is also the join key between
the upload and Open WebUI's vector-store collection (see
`data/open-webui/vector_db/<uuid4>/`).

`<safe_original_filename>` is the original filename as supplied by the
browser, with characters deemed unsafe by browsers sanitised. Spaces and
dots are preserved in the examples we have inspected.

Examples observed in this deployment (as of 2026-09):

- `data/open-webui/uploads/07f8f033-7147-459f-9492-4b4dc0cba29b_Retirement - 2026.xlsx`
- `data/open-webui/uploads/6b62b0a5-32db-45f1-b68b-ef6e87e3dc41_AI Experiment RL and TB.docx`
- `data/open-webui/uploads/7713424d-7682-46c4-9524-251f718d50aa_Retirement - 2026.xlsx`
- `data/open-webui/uploads/c4b38e09-0ec4-4d69-a2ac-62324da09ecf_README.md`
- `data/open-webui/uploads/f2a69037-12c6-4331-b2e2-831f3d2e17a6_Retirement - 2026.xlsx`

## Ownership and permissions

- All files: `root:root`, mode `0644`.
- The Open WebUI container itself is run as `user: 0:0` (root) in
  `docker-compose.yml`, so ownership is consistent across uploads.
- There is no per-user subdirectory. With `WEBUI_AUTH=false` any user can
  upload, and any reader can list everything under `uploads/`. This is
  intentional for the deployment but worth noting if multi-user auth is
  ever enabled.

## How the hermes gateway sees them

The hermes gateway compose (`hermes-stack` stack, service `hermes`) has:

    - ./data/open-webui/uploads:/opt/uploads:ro

i.e. the same host directory is bind-mounted read-only into the hermes
container at `/opt/uploads/`. The hermes process inside the container can
therefore read every attachment the Open WebUI instance produced.

Sandboxes (`nikolaik/python-nodejs`) do **not** carry this bind; if a
future skill needs to operate on uploads from inside a sandbox, the
`TERMINAL_DOCKER_VOLUMES` list in `data/.env` (which must mirror
`config.yaml -> terminal.docker_volumes`) must be extended.

## How to enumerate attachments

From inside the gateway:

    ls -lt /opt/uploads/

sorts newest first by mtime, which approximates "most recent attachment" for
chat workflows.

To match by original name:

    ls /opt/uploads/*"<safe-name>"*

The stem-then-suffix trick avoids confusion between the UUID prefix and the
literal filename.

## Why this exists as a separate doc

The skill body (`SKILL.md`) gives the high-level procedure. This reference
is the place to update if anything in the Open WebUI storage layout
changes (e.g. a future version introduces per-user subdirectories or
changes the data root).
