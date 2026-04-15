---
name: generic‑bootstrap
description: |
  Runs *all* executable scripts found in the `scripts/` folder when the
  agent starts.  Use it to guarantee that any prerequisite skill‑setup
  (installing CLI tools, pulling credentials, seeding data, etc.) is
  performed automatically.
version: 1.0.0
author: your‑name <you@example.com>
license: MIT
requires_toolsets: [terminal]        # we need the terminal tool to execute shell code
metadata:
  hermes:
    tags: [bootstrap, startup, automation]
    related_skills: []               # add any skills that depend on this one, if you wish
on_startup: |
  # -----------------------------------------------------------------
  # Generic bootstrap – run every executable script in ./scripts/
  # -----------------------------------------------------------------
  # The `terminal` tool launches a shell command.  We pass a short
  # Bash one‑liner that discovers and executes each script in order.
  # `set -euo pipefail` makes the whole bootstrap fail early if any
  # script returns a non‑zero exit code (Hermes will surface the error).
  #
  # If you want a *best‑effort* run (continue even if one script fails),
  # replace `set -e` with `set +e` inside the quoted block.
  #
  terminal(
    command="""
      set -euo pipefail
      SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/scripts"
      if [[ ! -d "$SCRIPT_DIR" ]]; then
        echo "⚠️ No scripts/ directory found – nothing to run."
        exit 0
      fi

      echo "🔧 Running bootstrap scripts from $SCRIPT_DIR ..."
      # Sort for deterministic order (lexicographic)
      for script in "$(ls -1 "$SCRIPT_DIR" | sort)"; do
        full_path="$SCRIPT_DIR/$script"
        if [[ -x "$full_path" && -f "$full_path" ]]; then
          echo "▶️ Executing $script"
          "$full_path"
          echo "✅ $script finished"
        else
          echo "⏭️ Skipping $script (not executable or not a regular file)"
        fi
      done
      echo "🎉 All bootstrap scripts have completed."
    """,
    timeout=300,                     # increase if you expect long‑running scripts
    pty=false                        # plain non‑interactive shell
  )
---
# Generic Bootstrap Skill

## Purpose
This skill does **not expose any user‑facing commands**.  
Its sole responsibility is to make sure that, **as soon as the Hermes
agent starts**, every script you place under the `scripts/` directory is
run exactly once, in alphabetical order.

## How it works
1. The `on_startup:` block is a special hook that Hermes executes right
   after the skill catalog has been loaded and **before the first user
   message is processed**.
2. Inside the hook we call the `terminal` tool with a Bash one‑liner that:
   * Resolves the absolute path of the `scripts/` folder.
   * Lists the files inside it, sorts them alphabetically (so the order is deterministic).
   * For each **executable regular file**, it runs the script.
   * Prints a short status line before and after each script.
3. If any script exits with a non‑zero status, the whole bootstrap fails
   (because of `set -euo pipefail`).  Hermes will surface the error to
   the logs – you can change `set -e` to `set +e` if you prefer “best‑effort”.

## Adding a new bootstrap script
1. Create a new file under `scripts/`, e.g. `scripts/prepare‑todoist.sh`.
2. Make it executable: `chmod +x scripts/prepare‑todoist.sh`.
3. Write any shell commands you need (install a CLI tool, export env vars,
   run `td skill install universal`, etc.).
4. **No further changes to `SKILL.md` are required** – the next time the
   agent starts, the script will be picked up automatically.

### Example script (install Todoist‑CLI if missing)

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! command -v td >/dev/null; then
  echo "✅ Todoist‑CLI not found – installing via npm..."
  npm i -g @doist/todoist-cli
  echo "✅ Todoist‑CLI installed."
else
  echo "✅ Todoist‑CLI already present – nothing to do."
fi

# Ensure the Todoist skill itself is loaded for the universal agent
if ! hermes skill list --output names | grep -q '^todoist-cli$'; then
  echo "⚡ Installing Todoist‑CLI skill for the universal agent..."
  td skill install universal
  echo "✅ Todoist‑CLI skill installed."
fi
