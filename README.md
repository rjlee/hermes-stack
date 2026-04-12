# Hermes + OpenWebUI Stack

## Overview
This repository contains a Docker‑Compose setup that runs:
- **OpenWebUI** (a ChatUI front‑end) on port `8001`
- **Hermes** (the OpenAI‑compatible API server) on port `8642`
- **CamoFox Browser** (headless browser for agent tasks) on port `9377` (internal only)
- **Life360 MCP** (location tracking API) on port `8123` (internal only)
- The **OpenCode CLI** is baked into the Hermes image via the `hermes‑init/` scripts.

All services store their persistent data under a single top‑level `data/` directory:
- `data/open-webui` → OpenWebUI backend files
- `data/hermes`   → Hermes `/opt/data`
- `data/camofox-browser` → CamoFox browser data
- `data/life360-mcp` → Life360 MCP cache and state

The `workspace/` directory is mounted for you to keep any local code or notebooks you want Hermes to see.

## Environment variables
Create a `.env` file from the provided template and fill in the required values.  The table below shows the defaults for the optional variables.

| Variable | Required? | Default | Description |
|---|---|---|---|
| `API_SERVER_KEY` | **Yes** | – | Secret token required by the Hermes API. |
| `WEBUI_SECRET_KEY` | **Yes** | – | Secret key for Open‑WebUI sessions. |
| `OPENAI_API_KEY` | **Yes** | – | API key for OpenAI (or compatible) backend. |
| `WORKSPACE_DIR` | No | `./workspace` | Directory mounted into containers for local code/notebooks. |
| `ENABLE_SIGNUP` | No | `true` | Whether new users can self‑register in OpenWebUI. |
| `WEBUI_AUTH` | No | `none` | Authentication mode for OpenWebUI (`none`, `ldap`, etc.). |

## Quick Start

```bash
# 1️⃣ Copy the environment template and fill in your secrets
cp .env.example .env
# edit .env and set the values (API keys, passwords, etc.)
```

```bash
# 2️⃣ Start the stack
./hermes-stack up
```

```bash
# 3️⃣ Verify everything is healthy
./hermes-stack logs   # follow the logs, or `docker compose ps`
# Both services should show "healthy"
```

```bash
# 4️⃣ Test the OpenCode CLI inside the Hermes container (no API key needed)
./hermes-stack status
docker exec hermes which opencode   # → /usr/local/bin/opencode
docker exec hermes opencode --version
```

## Available Commands

| Command | Description |
|---------|-------------|
| `./hermes-stack up` | Start the stack. Use --upgrade to pull latest images and rebuild Hermes. |
| `./hermes-stack up --upgrade` | Pull latest images and rebuild Hermes |
| `./hermes-stack restart` | Stop and start containers. Use --upgrade to pull latest and rebuild. |
| `./hermes-stack backup [--retain N] [--dry-run]` | Create a timestamped backup of `data/` and `workspace/`. Keeps the most recent 7 archives by default. |
| `./hermes-stack restore` | Restore from a backup |
| `./hermes-stack prune` | Remove unused Docker images and volumes |
| `./hermes-stack status` | Show container health |
| `./hermes-stack check-env` | Validate required environment variables |
| `./hermes-stack upgrade-base` | Pull latest Hermes‑Agent and show new digest |
| `./hermes-stack help` | Show this help |

## Advanced Build Options

When you upgrade the stack (via `./hermes-stack up --upgrade` or `./hermes-stack restart --upgrade`), the script pulls the latest Docker images and rebuilds the Hermes image, passing two build‑args to the Dockerfile:

- **`BASE_IMAGE`** – the full image reference of the upstream Hermes Agent, pinned to a specific digest (e.g. `nosresearch/hermes-agent@sha256:abcd…`).
- **`BASE_DIGEST`** – the raw digest string (`sha256:abcd…`) that is also written into the image as the OCI label `org.opencontainers.image.revision`.

These arguments ensure the custom Hermes image is reproducible and that the `status` command can report the exact upstream version. The Dockerfile now also includes additional OCI metadata (`title`, `version`, `created`).

If you need to build the image manually, you can run:

```bash
docker build -f Dockerfile.hermes \
    --build-arg BASE_IMAGE=nosresearch/hermes-agent@sha256:<digest> \
    --build-arg BASE_DIGEST=sha256:<digest> \
    -t hermes-stack-hermes .
```

Replace `<digest>` with the digest you obtain from `docker manifest inspect nosresearch/hermes-agent:latest`.

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

The OpenCode CLI is bundled in the Hermes image. It uses the **free `gpt-5-nano` model**, which does **not require an API key**. Verify it works inside the container:

```bash
docker exec hermes which opencode   # → /usr/local/bin/opencode
docker exec hermes opencode --version
```

The `opencode.json` configuration only needs to specify the model (already set to `opencode/gpt-5-nano`).

## Common Issues & Fixes
| Symptom | Likely cause | Fix |
|---|---|---|
| `hermes` container restarts repeatedly | Missing `API_SERVER_KEY` or malformed `.env` | Ensure `.env` contains a valid `API_SERVER_KEY` and run `./hermes-stack up` |
| OpenWebUI cannot reach Hermes (`/v1` errors) | Network issue – services not on the same bridge | Both services are attached to `hermesnet`; ensure you didn't modify the network name |
| Data not persisting after `docker compose down` | Used `docker compose down -v` which removes volumes | Omit `-v` flag; the `data/` directories are bind‑mounted, they stay on the host |
| Need to add a new init step for Hermes | New script required at image build time | Drop a `*.sh` file into `hermes-init/` and rebuild (`./hermes-stack up`) |

## Extending the Stack

- **Add GPU support**: create a `docker-compose.gpu.yml` with a devices reservation block and start with `docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d`.

- **MCP Servers**: Add MCP (Model Context Protocol) servers to extend Hermes with additional tools. Configure in `data/hermes/config.yaml`:

```yaml
mcp_servers:
  life360:
    url: http://life360-mcp:8123
  # Add more MCP servers as needed:
  # filesystem:
  #   command: npx
  #   args: ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
  # github:
  #   command: npx
  #   args: ["-y", "@modelcontextprotocol/server-github"]
  #   env:
  #     GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_..."
```

- **Separate OpenCode config**: the `opencode_cfg` volume stores `~/.config/opencode`. Edit its contents by running `docker exec -it hermes bash` and modifying `/root/.config/opencode/opencode.json`.

- **Pin OpenCode version**: edit `hermes-init/install-opencode.sh` to use a fixed release URL instead of the "latest" endpoint.

## Cleanup
```bash
# Stop everything
./hermes-stack down

# Remove the built Hermes image (optional)
docker image rm hermes-project_hermes
```

---
*Maintained by @rjlee*