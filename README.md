# Hermes Stack

## Overview

This repository contains a Docker‑Compose setup that runs:
- **OpenWebUI** (a ChatUI front‑end) on port `8001`
- **Hermes** (the agent framework) on its internal port `8642`, accessed via OpenWebUI
- **CamoFox Browser** (headless browser for agent tasks) on port `9377` (internal only)
- The **Life360 CLI**, **Todoist CLI**, and **OpenCode CLI** are installed at runtime via the bootstrap hook.

The stack uses the standard `nousresearch/hermes-agent` image.

All services store their persistent data under a single top‑level `data/` directory:
- `data/open-webui` → OpenWebUI backend files
- `data/hermes`   → Hermes `/opt/data` (host `/opt/data` is a symlink to this repo dir — single source of truth; sandbox + gateway converge; do not replace the symlink with a real dir)
- `data/camofox-browser` → CamoFox browser data

The `workspace/` directory is mounted for you to keep any local code or notebooks you want Hermes to see.

## Quick Start

```bash
# 1️⃣ Set up secrets, sandbox mounts, terminal backend & performance defaults
#    (also installs skills, hints, bootstraps and hooks)
./hermes-stack setup

# 2️⃣ Start the stack
./hermes-stack up

# 3️⃣ Verify everything is healthy
./hermes-stack status
```

## Configuration

### Environment files

The `./hermes-stack setup` command creates the necessary `.env` files and generates secrets automatically:

| File | Variables | Description |
|---|---|---|
| `data/.env` | `API_SERVER_KEY`, `WORKSPACE_DIR`, `TERMINAL_DOCKER_VOLUMES`, `TERMINAL_DOCKER_EXTRA_ARGS` | Root config: shared secrets + sandbox volume mounts (single source of truth shared by the gateway and `cli`) |
| `data/hermes/.env` | `TODOIST_API_TOKEN`, `LIFE360_AUTHORIZATION`, service overrides | Hermes service env (set via `setup todoist` / `setup life360`; kept minimal — terminal/sandbox settings live in `data/.env`) |
| `data/open-webui/.env` | `WEBUI_SECRET_KEY` | OpenWebUI config |
| `data/camofox-browser/.env` | `CAMOFOX_PORT`, `CAMOFOX_HEADLESS`, etc. | CamoFox webserver config |

Sandbox env injection
---------------------
Every variable in `data/hermes/.env` is injected into every sandbox container automatically via the `--env-file /opt/data/.env` flag in `terminal.docker_extra_args`. Because the Docker CLI runs inside the gateway container (where `/opt/data` = host `data/hermes/`), the full hermes env file — `TODOIST_API_TOKEN`, `LIFE360_AUTHORIZATION`, `GOOGLE_*`, `WHATSAPP_*`, etc. — lands in the sandbox at spawn time without any per-var whitelist. Only `API_SERVER_KEY` (which lives in `data/.env`, not `data/hermes/.env`) is forwarded separately via `docker_forward_env` in `config.yaml`. To make a new token visible in the sandbox, simply add it to `data/hermes/.env`; no `config.yaml` change is needed.

Sandbox mounts are declared in `data/.env` via `TERMINAL_DOCKER_VOLUMES` (JSON array of `host:container[:ro]` specs) — not in `config.yaml` — so a config reseed from `cli-config.yaml.example` can never drop them. Repo-relative paths use a `@REPO_DIR@` placeholder that `./hermes-stack setup` replaces with the absolute repo path. JSON values are single-quoted so `./hermes-stack` can `source` the file in bash; docker `--env-file` consumers (`cli`, `run`, `setup`) receive a quote-stripped copy automatically.

### Image overrides

By default, the stack uses `nousresearch/hermes-agent:latest`. Override it by setting `HERMES_IMAGE` in `.env`:

```bash
HERMES_IMAGE=nousresearch/hermes-agent:v2026.4.8
```

When you run `./hermes-stack up --upgrade`, the script pulls the latest images.

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
| `./hermes-stack install skills` | Install skills from `./skills/` (includes per‑skill hints and bootstraps) |
| `./hermes-stack install hints` | Install standalone hints from `./hints/` |
| `./hermes-stack install bootstraps` | Install standalone bootstrap scripts from `./bootstrap/` |
| `./hermes-stack install hooks` | Install hook handlers from `./hooks/` |
| `./hermes-stack run <command>` | Run an arbitrary command in a fresh hermes container |
| `./hermes-stack cli` | Spawn an interactive hermes container (CLI mode) |
| `./hermes-stack say <message>` | Send a chat message to Hermes and print the response (`--output=json` for the full JSON) |
| `./hermes-stack backup [--retain N] [--dry-run]` | Create a timestamped backup of `data/` and `workspace/`. Keeps the most recent 7 archives by default. |
| `./hermes-stack restore` | Restore from a backup |
| `./hermes-stack prune` | Remove unused Docker images and volumes |
| `./hermes-stack check-env` | Validate required environment variables |
| `./hermes-stack upgrade-base` | Pull latest Hermes‑Agent and show new digest |
| `./hermes-stack reset [services]` | Reset data directories for one or more services (default: all). Backs up `.env` to `.env.backup` |
| `./hermes-stack help` | Show this help |

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

## Skills, Hints & Bootstraps

### Skills

Add skills to the top‑level `skills/` directory. The expected layout is `skills/<group>/<skill-name>/`:

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

Run `./hermes-stack install skills` to deploy skills from `./skills/`.

Each installable has its own command:

| Command | Installs from | Description |
|---------|---------------|-------------|
| `install skills` | `./skills/` | Skills, per‑skill hints, and per‑skill bootstrap scripts |
| `install hints` | `./hints/` | Standalone memory‑seeding hints |
| `install bootstraps` | `./bootstrap/` | Standalone bootstrap scripts (e.g. `30-install-opencode.sh`) |
| `install hooks` | `./hooks/` | Hook handlers (e.g. the bootstrap hook that runs the installed `bootstrap/*.sh` at container startup) |

All use `--force` to overwrite existing files.

To pin a specific version (e.g. OpenCode), edit the corresponding script in `bootstrap/` (tracked in git) and change the release URL.

### Hooks

Hooks deploy event handlers into `data/hermes/hooks/<name>/`. Each hook is a directory containing a `HOOK.yaml` manifest and a `handler.py` (e.g. `hooks/bootstrap/` runs the installed `bootstrap/*.sh` scripts at container startup). Install them with `./hermes-stack install hooks`; `./hermes-stack setup` also runs this for you.

## OpenCode CLI

The OpenCode CLI is installed at runtime via the bootstrap hook and configured to use a **local LLM provider** — no API key required. Verify it works inside the container:

```bash
docker exec hermes-stack-hermes-1 which opencode   # → /opt/data/.local/bin/opencode
docker exec hermes-stack-hermes-1 opencode --version
```

The `opencode.json` configuration lives at `data/hermes/opencode.json` and is mounted into the container at `/opt/data/opencode.json`. Edit it to change providers or models.

## File Ownership

Each container runs under a different user ID:

| Service | UID | GID |
|---|---|---|
| Hermes | 10000 | 10000 |
| Open WebUI | root | root |
| CamoFox | node user | node user |

Files created inside a container are owned by that container's UID on the host.

## Common Issues & Fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Sandbox (execute_code) volumes missing / dropped | `TERMINAL_DOCKER_VOLUMES` invalid or absent in `data/.env` | Re-run `./hermes-stack setup`, or check the value is a single-quoted JSON array of `host:container[:ro]` specs |
| `hermes` container restarts repeatedly | Missing `API_SERVER_KEY` or malformed `data/.env` | Ensure `data/.env` contains a valid `API_SERVER_KEY` and run `./hermes-stack up` |
| OpenWebUI cannot reach Hermes (`/v1` errors) | Network issue – services not on the same bridge | Both services are attached to `hermesnet`; ensure you didn't modify the network name |
| Data not persisting after `docker compose down` | Used `docker compose down -v` which removes volumes | Omit `-v` flag; the `data/` directories are bind‑mounted, they stay on the host |
| Need to add a new init step for Hermes | New script required at container startup | Add an `install.sh` inside the skill directory, or drop a `*.sh` into `bootstrap/` |
| Need to add Todoist skills | Install skills for Todoist CLI | Run `./hermes-stack setup todoist` |
| Need to add Life360 skills | Install skills for Life360 CLI | Run `./hermes-stack setup life360` |
| Need Google Workspace (Gmail, Calendar, Drive) | Configure OAuth in Google Cloud Console | Run `./hermes-stack setup google-workspace` and follow prompts |
| Cannot edit files in `data/hermes/` | Container (UID 10000) owns files, not your host user | Run `sudo chmod -R o+rX data/hermes` to make them readable without breaking container write access |
| `l360`/`td`/`opencode` "not found" in sandbox | `config.yaml` bridge overrides `TERMINAL_DOCKER_EXTRA_ARGS` from `data/.env`, so the `.profile` mount / PATH never reach the container | Put `-e PATH=/opt/data/.local/bin:...` inside `terminal.docker_extra_args` in `config.yaml` (authoritative for the gateway tool), and keep `data/.env` in sync for the `cli`/`run` path |
| GPU support needed | No GPU devices in compose | Add a `docker-compose.gpu.yml` with NVIDIA device reservations |

---

*Maintained by @rjlee*