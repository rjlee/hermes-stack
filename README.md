# Hermes + OpenWebUI Stack

## Overview
This repository contains a Docker‑Compose setup that runs:
- **OpenWebUI** (a ChatUI front‑end) on port `8001`
- **Hermes** (the OpenAI‑compatible API server) on port `8642` (internal only, accessed via OpenWebUI)
- **CamoFox Browser** (headless browser for agent tasks) on port `9377` (internal only)
- The **Life360 CLI** is installed at runtime via the bootstrap script.

The stack uses the standard `nousresearch/hermes-agent` image. The **OpenCode CLI** is installed at runtime via the bootstrap script.

All services store their persistent data under a single top‑level `data/` directory:
- `data/open-webui` → OpenWebUI backend files
- `data/hermes`   → Hermes `/opt/data` (includes Life360 CLI credentials)
- `data/camofox-browser` → CamoFox browser data

The `workspace/` directory is mounted for you to keep any local code or notebooks you want Hermes to see.

## Quick Start

```bash
# 1️⃣ Set up secrets (generates API_SERVER_KEY, WEBUI_SECRET_KEY, etc.)
./hermes-stack setup
```

```bash
# 2️⃣ Start the stack
./hermes-stack up
```

```bash
# 3️⃣ Verify everything is healthy
./hermes-stack status
```

## Environment variables

The `./hermes-stack setup` command creates the necessary `.env` files and generates secrets automatically:

| File | Variables | Description |
|---|---|---|
| `data/.env` | `API_SERVER_KEY`, `WORKSPACE_DIR` | Root config (shared secrets) |
| `data/hermes/.env` | `CAMOFOX_URL`, `TODOIST_API_TOKEN`, `LIFE360_AUTHORIZATION` | Hermes config (includes TODOIST_API_TOKEN and LIFE360_AUTHORIZATION) |
| `data/open-webui/.env` | `WEBUI_SECRET_KEY` | OpenWebUI config |
| `data/camofox-browser/.env` | (optional) CamoFox settings | CamoFox webserver config |

## Available Commands

| Command | Description |
|---------|-------------|
| `./hermes-stack up` | Start the stack. Use --upgrade to pull latest images and rebuild Hermes. |
| `./hermes-stack up --upgrade` | Pull latest images and rebuild Hermes |
| `./hermes-stack restart` | Stop and start containers. Use --upgrade to pull latest and rebuild. |
| `./hermes-stack reset` | Reset data directories (backups .env to .env.backup) |
| `./hermes-stack setup` | Set up secrets and run hermes setup in container |
| `./hermes-stack setup todoist` | Interactive Todoist setup + install todoist skills |
| `./hermes-stack setup life360` | Interactive Life360 setup + install life360 skills |
| `./hermes-stack setup google-workspace` | Configure Google Workspace OAuth (Gmail, Calendar, Drive) |
| `./hermes-stack profiles` | List available model profiles |
| `./hermes-stack profiles <name>` | Apply a model profile (e.g., free, free-nemo) |
| `./hermes-stack install skills` | Install skills from ./skills/ to data/hermes/ |
| `./hermes-stack backup [--retain N] [--dry-run]` | Create a timestamped backup of `data/` and `workspace/`. Keeps the most recent 7 archives by default. |
| `./hermes-stack restore` | Restore from a backup |
| `./hermes-stack prune` | Remove unused Docker images and volumes |
| `./hermes-stack status` | Show container health |
| `./hermes-stack check-env` | Validate required environment variables |
| `./hermes-stack upgrade-base` | Pull latest Hermes‑Agent and show new digest |
| `./hermes-stack cli` | Spawn an interactive hermes container (CLI mode) |
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

The OpenCode CLI is installed at runtime via the bootstrap script. It uses the **free `gpt-5-nano` model**, which does **not require an API key**. Verify it works inside the container:

```bash
docker exec hermes which opencode   # → /usr/local/bin/opencode
docker exec hermes opencode --version
```

The `opencode.json` configuration only needs to specify the model (already set to `opencode/gpt-5-nano`).

## Common Issues & Fixes
| Symptom | Likely cause | Fix |
|---|---|---|
| `hermes` container restarts repeatedly | Missing `API_SERVER_KEY` or malformed `data/.env` | Ensure `data/.env` contains a valid `API_SERVER_KEY` and run `./hermes-stack up` |
| OpenWebUI cannot reach Hermes (`/v1` errors) | Network issue – services not on the same bridge | Both services are attached to `hermesnet`; ensure you didn't modify the network name |
| Data not persisting after `docker compose down` | Used `docker compose down -v` which removes volumes | Omit `-v` flag; the `data/` directories are bind‑mounted, they stay on the host |
| Need to add a new init step for Hermes | New script required at container startup | Drop a `*.sh` file into `hermes-init/scripts/` and restart (`./hermes-stack restart`) |
| Need to add Todoist skills | Install skills for Todoist CLI | Run `./hermes-stack setup todoist` |
| Need to add Life360 skills | Install skills for Life360 CLI | Run `./hermes-stack setup life360` |
| Need Google Workspace (Gmail, Calendar, Drive) | Configure OAuth in Google Cloud Console | Run `./hermes-stack setup google-workspace` and follow prompts |

## Extending the Stack

- **Add GPU support**: create a `docker-compose.gpu.yml` with a devices reservation block and start with `docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d`.

- **Skills**: Add skills to the `skills/` directory. Each subdirectory represents an addon:  - `skills/todoist/` → Todoist CLI skills
  - `skills/life360/` → Life360 CLI skills

- **Pin OpenCode version**: edit `hermes-init/scripts/install-opencode.sh` to use a fixed release URL instead of the "latest" endpoint.

## Cleanup
```bash
# Stop everything
./hermes-stack down

# Remove the built Hermes image (optional)
docker image rm hermes-project_hermes
```

---
*Maintained by @rjlee*