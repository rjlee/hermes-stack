import asyncio
import logging
import os
import shutil
import subprocess
from pathlib import Path

logger = logging.getLogger("hooks.bootstrap")
BOOTSTRAP_DIR = Path("/opt/data/.hermes-stack/bootstrap")
HINTS_DIR = Path("/opt/data/.hermes-stack/hints")

def _needs_root(script_path):
    """Detect if a bootstrap script needs root privileges for privileged
    operations only. Root-free subcommands like `apt-get download`,
    `--simulate install`, or non-privileged scripts must NOT be flagged,
    otherwise the hook tries sudo/su and breaks non-root installs."""
    markers = (
        "apt-get install", "apt-get update", "apt-get remove", "apt-get purge",
        "apt install", "apt update", "apt remove", "apt purge",
        "dnf install", "dnf update", "yum install", "yum update",
        "pacman -", "usermod ", "useradd ", "groupmod ", "groupadd ",
    )
    try:
        content = Path(script_path).read_text()
        return any(marker in content for marker in markers)
    except Exception:
        return False

def _run_one(f):
    if _needs_root(f) and os.geteuid() != 0:
        sudo = shutil.which("sudo")
        if sudo:
            logger.warning("bootstrap: %s needs root, elevating via sudo", f.name)
            try:
                return subprocess.run(
                    [sudo, "-n", "bash", str(f)],
                    timeout=120, capture_output=True, text=True,
                )
            except Exception as e:
                logger.warning("bootstrap: %s sudo elevation error: %s", f.name, e)
                return None
        logger.warning(
            "bootstrap: %s needs root but no sudo is available; running as-is (may fail)",
            f.name,
        )
    return subprocess.run(["bash", str(f)], timeout=120, capture_output=True, text=True)

def _run():
    _run_scripts()
    _seed_hints()

def _run_scripts():
    if not BOOTSTRAP_DIR.exists():
        logger.warning("bootstrap: no scripts dir, skipping")
        return
    for f in sorted(BOOTSTRAP_DIR.iterdir()):
        if f.suffix == ".sh" and f.stat().st_mode & 0o100:
            logger.warning("bootstrap: running %s", f.name)
            try:
                result = _run_one(f)
                if result is None:
                    continue
                if result.returncode == 0:
                    logger.warning("bootstrap: %s completed", f.name)
                else:
                    logger.warning(
                        "bootstrap: %s failed (code %d): %s",
                        f.name, result.returncode, result.stderr[:200],
                    )
            except subprocess.TimeoutExpired:
                logger.warning("bootstrap: %s timed out after 120s", f.name)
            except Exception as e:
                logger.warning("bootstrap: %s error: %s", f.name, e)
        else:
            logger.warning("bootstrap: skipping %s (not executable .sh)", f.name)

def _seed_hints():
    if not HINTS_DIR.exists():
        logger.warning("bootstrap: no hints dir, skipping")
        return
    content = ""
    for f in sorted(HINTS_DIR.iterdir()):
        if f.is_file():
            content += f.read_text() + "\n---\n"
    if not content:
        logger.warning("bootstrap: no hints content, skipping")
        return
    prompt = "Remember these as persistent preferences. Only add new items - do NOT repeat anything already in your memory:\n" + content
    try:
        result = subprocess.run(
            ["hermes", "chat", "-q", prompt],
            timeout=300,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            logger.warning("bootstrap: hints seeded successfully")
        else:
            logger.warning("bootstrap: hints seed failed (code %d): %s", result.returncode, result.stderr[:200])
    except subprocess.TimeoutExpired:
        logger.warning("bootstrap: hints seed timed out after 300s")
    except Exception as e:
        logger.warning("bootstrap: hints seed error: %s", e)

async def handle(event_type, context):
    logger.warning("bootstrap: hook triggered on %s", event_type)
    await asyncio.to_thread(_run)