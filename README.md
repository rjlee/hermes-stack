# Hermes + OpenWebUI Stack

## Overview
This repository contains a Docker‑Compose setup that runs:
- **OpenWebUI** (a ChatUI front‑end) on port `8001`
- **Hermes** (the agent framework) on its internal port `8642`, accessed via OpenWebUI
- **CamoFox Browser** (headless browser for agent tasks) on port `9377` (internal only)
- The **Life360 CLI**, **Todoist CLI**, and **OpenCode CLI** are installed at runtime via the bootstrap hook.

The stack uses the standard `nousresearch/hermes-agent` image.

All services store their persistent data under a single top‑level `data/` directory:
- `data/open-webui` → OpenWebUI backend files
- `data/hermes`   → Hermes `/opt/data`
- `data/camofox-browser` → CamoFox browser data

The `workspace/` directory is mounted for you to keep any local code or notebooks you want Hermes to see.

## Quick Start

```bash
# 1️⃣ Set up secrets (generates API_SERVER_KEY, WEBUI_SECRET_KEY, etc.)
./hermes-stack setup

# 2️⃣ Start the stack
./hermes-stack up

# 3️⃣ Verify everything is healthy
./hermes-stack status
```

## Environment variables

The `./hermes-stack setup` command creates the necessary `.env` files and generates secrets automatically:

| File | Variables | Description |
|---|---|---|
| `data/.env` | `API_SERVER_KEY`, `WORKSPACE_DIR` | Root config (shared secrets) |
| `data/hermes/.env` | `TODOIST_API_TOKEN`, `LIFE360_AUTHORIZATION` | Hermes config (set via `setup todoist` / `setup life360`) |
| `data/open-webui/.env` | `WEBUI_SECRET_KEY` | OpenWebUI config |
| `data/camofox-browser/.env` | `CAMOFOX_PORT`, `CAMOFOX_HEADLESS`, etc. | CamoFox webserver config |

## Available Commands

| Command | Description |
|---------|-------------|
| `./hermes-stack up` | Start the stack. Use `--upgrade` to pull latest images. |
| `./hermes-stack down` | Stop and remove containers, networks, and default volumes |
| `./hermes-stack restart` | Stop and start containers. Use `--upgrade` to pull latest. |
| `./hermes-stack logs` | Follow live logs of all services |
| `./hermes-stack status` | Show container health |
| `./hermes-stack setup` | Set up secrets and run hermes setup in container |
| `./hermes-stack setup todoist` | Interactive Todoist setup + install todoist skills |
| `./hermes-stack setup life360` | Interactive Life360 setup + install location skills |
| `./hermes-stack setup google-workspace` | Configure Google Workspace OAuth (Gmail, Calendar, Drive) |
| `./hermes-stack model <name>` | Switch LLM model config (e.g., `model free`) |
| `./hermes-stack fix-perms` | Make `data/hermes/` files readable on the host |
| `./hermes-stack install skills` | Install skills, hints, and bootstrap install scripts from `./skills/` and `./bootstrap/` to `data/hermes/` |
| `./hermes-stack install hints` | Install memory‑seeding hints from `./hints/` |
| `./hermes-stack run <command>` | Run an arbitrary command in a fresh hermes container |
| `./hermes-stack cli` | Spawn an interactive hermes container (CLI mode) |
| `./hermes-stack backup [--retain N] [--dry-run]` | Create a timestamped backup of `data/` and `workspace/`. Keeps the most recent 7 archives by default. |
| `./hermes-stack restore` | Restore from a backup |
| `./hermes-stack prune` | Remove unused Docker images and volumes |
| `./hermes-stack check-env` | Validate required environment variables |
| `./hermes-stack upgrade-base` | Pull latest Hermes‑Agent and show new digest |
| `./hermes-stack reset [services]` | Reset data directories for one or more services (default: all). Backs up `.env` to `.env.backup` |
| `./hermes-stack help` | Show this help |

## Advanced Build Options

By default, the stack uses the standard `nousresearch/hermes-agent:latest` image. You can override it by setting `HERMES_IMAGE` in your `.env`:

```bash
HERMES_IMAGE=nousresearch/hermes-agent:v2026.4.8
```

When you upgrade with `--upgrade`, the script pulls the latest Docker images.

## Backup

The `backup` command supports two optional flags:

- `--retain N` – keep only the **most recent N** archives (default is **7**, but you can override the default globally with the environment variable `BACKUP_RETAIN_COUNT`).
- `--dry-run` – list the archives that would be pruned without actually deleting them.

Examples:

```bash
# Normal backup (keeps newest 7 archives)
./hermes-stack backup

# Keep only the 5 most recent backups
./hermes-stack backup --retain 5

# See what would be removed without deleting anything
./hermes-stack backup --dry-run
```

## OpenCode CLI

The OpenCode CLI is installed at runtime via the bootstrap hook and configured to use a **local LLM provider** — no API key required. Verify it works inside the container:

```bash
docker exec hermes-stack-hermes-1 which opencode   # → /opt/data/.local/bin/opencode
docker exec hermes-stack-hermes-1 opencode --version
```

The `opencode.json` configuration lives at `data/hermes/opencode.json` and is mounted into the container at `/opt/data/opencode.json`. Edit it to change providers or models.

## Common Issues & Fixes
| Symptom | Likely cause | Fix |
|---|---|---|
| `hermes` container restarts repeatedly | Missing `API_SERVER_KEY` or malformed `data/.env` | Ensure `data/.env` contains a valid `API_SERVER_KEY` and run `./hermes-stack up` |
| OpenWebUI cannot reach Hermes (`/v1` errors) | Network issue – services not on the same bridge | Both services are attached to `hermesnet`; ensure you didn't modify the network name |
| Data not persisting after `docker compose down` | Used `docker compose down -v` which removes volumes | Omit `-v` flag; the `data/` directories are bind‑mounted, they stay on the host |
| Need to add a new init step for Hermes | New script required at container startup | Drop a `*.sh` file into `data/hermes/.hermes-stack/bootstrap/` and restart |
| Need to add Todoist skills | Install skills for Todoist CLI | Run `./hermes-stack setup todoist` |
| Need to add Life360 skills | Install skills for Life360 CLI | Run `./hermes-stack setup life360` |
| Need Google Workspace (Gmail, Calendar, Drive) | Configure OAuth in Google Cloud Console | Run `./hermes-stack setup google-workspace` and follow prompts |

## Extending the Stack

- **Add GPU support**: create a `docker-compose.gpu.yml` with a devices reservation block and start with `docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d`.

- **Skills**: Add skills to the top‑level `skills/` directory. The expected layout is `skills/<group>/<skill-name>/`:
  ```
  skills/
  ├── life360/
  │   └── location-query/       # Hermes skill
  │       ├── hints              # memory‑seeding hints
  │       └── install.sh         # bootstrap script (runs at container startup)
  ├── todoist/
  │   └── task-query/            # Hermes skill
  │       ├── hints              # memory‑seeding hints
  │       └── install.sh         # bootstrap script (runs at container startup)
  ├── google-workspace/
  │   └── hints                  # group‑level hints (no individual skills)
  └── mcp/
      └── life360-location-awareness/  # MCP server config
  ```
  Each skill can include:
  - `hints` — memory‑seeding hints for the agent
  - `install.sh` — a script copied to `data/hermes/.hermes-stack/bootstrap/` and run on container startup (for installing CLI tools, etc.)
  
  Run `./hermes-stack install skills` to deploy them into `data/hermes/`.

- **Hints**: Place general hints (not tied to a specific skill) directly in `hints/` at the repo root. Run `./hermes-stack install hints` to deploy them.

- **Bootstraps**: Place standalone bootstrap scripts (not tied to a specific skill) in `bootstrap/` at the repo root. They are copied to `data/hermes/.hermes-stack/bootstrap/` during `install skills` and run on every container startup. Example: `bootstrap/install-opencode.sh`.

- **Per‑skill bootstraps**: If a skill needs a CLI tool installed, add an `install.sh` inside the skill directory. It gets copied to the bootstrap directory automatically during `install skills`. See the `install.sh` examples under `skills/life360/` and `skills/todoist/`.

- **Pin OpenCode version**: edit `bootstrap/install-opencode.sh` (tracked in git) to use a fixed release URL instead of the "latest" endpoint.

## Cleanup
```bash
# Stop everything
./hermes-stack down
```

---

*Maintained by @rjlee*