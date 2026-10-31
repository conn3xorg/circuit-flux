#!/usr/bin/env sh
# Runs a small Git server over SSH on the throwaway host, using the sshd it
# already has, and writes what Conn3x needs to reach it to git.auto.tfvars and
# git_key. No Git hosting account is involved. Run it after up.sh.
set -eu
cd "$(dirname "$0")"
name=${NAME:-circuit-flux}
podman=${PODMAN:-podman}
# The address the pods reach the host on, not the forwarded one on 127.0.0.1.
host=$($podman inspect -f '{{.NetworkSettings.IPAddress}}' "$name")
[ -n "$host" ] || host=$($podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")

$podman exec -i "$name" sh -s < git-server.sh
$podman exec "$name" cat /root/flux_git_key > git_key
chmod 600 git_key
known_hosts=$($podman exec "$name" ssh-keyscan -t ed25519 "$host" 2>/dev/null | grep -v '^#')
[ -n "$known_hosts" ] || { echo "Couldn't read the host key from $host." >&2; exit 1; }
cat > git.auto.tfvars <<VARS
git_host        = "$host"
git_known_hosts = "$known_hosts"
VARS
echo "Git server ready at ssh://git@$host/srv/git/demo.git"
echo 'Now run: export TF_VAR_git_ssh_private_key="$(cat git_key)"'
