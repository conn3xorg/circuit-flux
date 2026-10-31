#!/usr/bin/env sh
# Run this on the k3s server, as root: it shows Flux pulled the repository over
# SSH, and that a commit reaches the cluster with no apply in between. It
# changes one ConfigMap and deletes another, which covers an update and a prune.
set -eu
kc="k3s kubectl"
value() { $kc -n default get configmap hello -o jsonpath='{.data.greeting}'; }

$kc -n flux-system wait gitrepository/flux-system kustomization/flux-system --for=condition=Ready --timeout=2m >/dev/null
[ "$(value)" = first ] || { echo "The ConfigMap in the repository didn't reach the cluster." >&2; exit 1; }
$kc -n default get configmap goes-away >/dev/null
echo "first commit: in the cluster"

# As the git user, since Git won't read a repository another user owns.
su -s /bin/sh git -c "set -eu
  work=\$(mktemp -d)
  git clone -q /srv/git/demo.git \$work
  sed -i 's/greeting: first/greeting: second/' \$work/hello.yaml
  git -C \$work rm -q goes-away.yaml
  git -C \$work add .
  git -C \$work -c user.name=demo -c user.email=demo@example.org commit -q -m second
  git -C \$work push -q origin main
  rm -rf \$work"

# The example's interval is 30s, and each of the two controllers has one.
for _ in $(seq 36); do
  if [ "$(value)" = second ] && ! $kc -n default get configmap goes-away >/dev/null 2>&1; then
    echo "second commit: reached the cluster, and the deleted ConfigMap is gone"
    exit 0
  fi
  sleep 5
done
echo "The second commit didn't reach the cluster in 3 minutes: greeting=$(value)" >&2
$kc -n flux-system get gitrepository,kustomization >&2
exit 1
