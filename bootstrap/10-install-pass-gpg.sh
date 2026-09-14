#!/usr/bin/env bash
# -----------------------------------------------------------------
# 10-install-pass-gpg.sh
#   Provisions a root-free gnupg + pass + tree into /opt/data/.local
#   so the hermes runtime AND every sandbox (which puts
#   /opt/data/.local/bin first on PATH and mounts /srv/pass +
#   /srv/pass-gnupg) gets working `pass`/`gpg` lookups.
#
#   The hermes image is Debian trixie but does not bake pass/gpg in,
#   and the bootstrap hook runs as the non-root hermes user, so
#   privileged package installation is impossible.  Instead we:
#     - apt-get download the .debs (no root needed; package lists
#       ship with the image),
#     - unpack them with dpkg-deb -x into /opt/data/.local,
#     - generate thin wrappers that set LD_LIBRARY_PATH/PATH so the
#       unpacked gpg/agent/shared-libs resolve correctly.
#
#   root-free: /opt/data is owned by the hermes runtime user.
#   idempotent: a marker is written only after a successful install.
# -----------------------------------------------------------------

set -euo pipefail

PREFIX="/opt/data/.local"
MARKER="${PREFIX}/.pass-gpg.ok"
PKGS="gnupg pass tree"

# --- idempotence -------------------------------------------------
if [ -f "${MARKER}" ] && [ -x "${PREFIX}/bin/gpg" ] && [ -x "${PREFIX}/bin/pass" ]; then
  echo "[bootstrap] pass/gpg already provisioned - skipping"
  exit 0
fi

MULTIARCH="lib/$(dpkg --print-architecture | sed \
  -e 's/^amd64$/x86_64-linux-gnu/' \
  -e 's/^arm64$/aarch64-linux-gnu/')"

WORK="$(mktemp -d /tmp/pass-gpg.XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

echo "[bootstrap] resolving dependency set for: ${PKGS} ..."
DEPS=($(apt-get --simulate install -y --no-install-recommends ${PKGS} 2>/dev/null |
  awk '/^Inst / {print $2}'))
if [ "${#DEPS[@]}" -eq 0 ]; then
  echo "[bootstrap] ERROR: could not resolve install set (apt lists missing?)" >&2
  exit 1
fi

echo "[bootstrap] downloading ${#DEPS[@]} packages: ${DEPS[*]} ..."
if ! (cd "${WORK}" && apt-get download "${DEPS[@]}" >/dev/null); then
  echo "[bootstrap] ERROR: apt-get download failed" >&2
  exit 1
fi

echo "[bootstrap] unpacking into ${PREFIX} ..."
for deb in "${WORK}"/*.deb; do
  dpkg-deb -x "${deb}" "${PREFIX}"
done

if [ -z "$(ls -A "${PREFIX}/usr/bin" 2>/dev/null)" ]; then
  echo "[bootstrap] ERROR: nothing unpacked from downloaded packages" >&2
  exit 1
fi

mkdir -p "${PREFIX}/bin"

echo "[bootstrap] generating wrappers ..."
for exe in "${PREFIX}/usr/bin/"*; do
  [ -e "${exe}" ] || continue
  name="$(basename "${exe}")"
  cat > "${PREFIX}/bin/${name}" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="${PREFIX}/usr/${MULTIARCH}"
export PATH="${PREFIX}/usr/bin:\$PATH"
exec "${exe}" "\$@"
EOF
  chmod 755 "${PREFIX}/bin/${name}"
done

# --- sanity ------------------------------------------------------
if [ ! -x "${PREFIX}/bin/gpg" ] || [ ! -x "${PREFIX}/bin/pass" ]; then
  echo "[bootstrap] ERROR: gpg/pass wrapper missing after install" >&2
  exit 1
fi

GPG_VERSION="$("${PREFIX}/bin/gpg" --version 2>/dev/null | head -1)" \
  || { echo "[bootstrap] ERROR: unpacked gpg fails to run" >&2; exit 1; }

touch "${MARKER}"
echo "[bootstrap] ${GPG_VERSION}"
echo "[bootstrap] pass/gpg provisioned in ${PREFIX}/bin"