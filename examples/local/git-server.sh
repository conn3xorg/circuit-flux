#!/usr/bin/env sh
# Run this as root on the host: makes a git user limited to git-shell, a key
# for Flux to log in with, and a bare repository holding two ConfigMaps.
set -eu
if command -v apt-get >/dev/null; then
  apt-get update -qq >/dev/null && apt-get install -y -qq git >/dev/null
else
  dnf -y -q install git-core shadow-utils >/dev/null
fi

id git >/dev/null 2>&1 || useradd -m -s "$(command -v git-shell)" git
# A locked account can't log in over SSH on some distros, even with a key.
usermod -p '*' git
[ -f /root/flux_git_key ] || ssh-keygen -q -t ed25519 -N '' -C flux -f /root/flux_git_key
install -d -m 700 -o git -g git /home/git/.ssh
install -m 600 -o git -g git /root/flux_git_key.pub /home/git/.ssh/authorized_keys
restorecon -R /home/git/.ssh 2>/dev/null || true

mkdir -p /srv/git
git init -q --bare -b main /srv/git/demo.git
work=$(mktemp -d)
git clone -q /srv/git/demo.git "$work" 2>/dev/null
cat > "$work/hello.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello
  namespace: default
data:
  greeting: first
YAML
sed 's/name: hello/name: goes-away/' "$work/hello.yaml" > "$work/goes-away.yaml"
git -C "$work" add .
git -C "$work" -c user.name=demo -c user.email=demo@example.org commit -q -m "first"
git -C "$work" push -q origin main
rm -rf "$work"
chown -R git:git /srv/git
