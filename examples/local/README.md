# Local example

Builds a one-node k3s cluster with [circuit-k3s](https://github.com/conn3xorg/circuit-k3s) in a throwaway Rocky Linux 10 container, runs a small Git server on that same host, and points Flux at it. You need Conn3x and Podman, and no Git hosting account.

k3s runs containers of its own, so the host container runs privileged, and rootless Podman can't give it the cpuset cgroup k3s needs. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
./git.sh
export TF_VAR_git_ssh_private_key="$(cat git_key)"
conn3x init
conn3x apply
conn3x plan
```

The apply takes a few minutes, and the second plan says `No changes.`

[git.sh](git.sh) runs [git-server.sh](git-server.sh) on the host, which makes a `git` user limited to `git-shell` and a repository at `/srv/git/demo.git` holding two ConfigMaps. It leaves a private key in `git_key`, and writes the host's address and host key to `git.auto.tfvars`. The key reaches Conn3x through `TF_VAR_git_ssh_private_key`, the way yours would, so it isn't in `terraform.tfstate`. Look for yourself.

To see a commit reach the cluster, run [check.sh](check.sh) on the host:

```sh
podman exec -i circuit-flux sh -s < check.sh
```

It checks the ConfigMaps got there, commits a change to one and deletes the other, then waits. Flux picks it up within the example's 30-second interval with no apply involved, and the deleted ConfigMap goes too. It only passes once, since the repository has moved on after that.

The container can't load kernel modules, so its host needs `br_netfilter` and `overlay` loaded. A Podman machine has both. On Linux, run `sudo modprobe -a br_netfilter overlay` first.

`up.sh` listens on `127.0.0.1:2318`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` stops the container, which removes it and its volume since it started with `--rm`, and deletes the keys and the state.
