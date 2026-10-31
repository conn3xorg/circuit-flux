#!/usr/bin/env sh
# Stops the container, which removes it and its volume since up.sh started it
# with --rm, and deletes everything up.sh, git.sh and Conn3x created here.
set -eu
cd "$(dirname "$0")"
${PODMAN:-podman} stop -i "${NAME:-circuit-flux}" >/dev/null 2>&1 || true
rm -rf id_ed25519 id_ed25519.pub known_hosts git_key git.auto.tfvars .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
