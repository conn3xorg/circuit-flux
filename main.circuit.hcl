locals {
  dir     = "/var/lib/conn3x-flux"
  etc     = "/etc/rancher/flux"
  git_dir = "${local.etc}/git"
  install = "${local.dir}/install-${var.flux_version}.yaml"
  sync    = "${local.etc}/sync.yaml"

  # Reads the binary rather than the API, so a plan doesn't depend on the
  # cluster being up.
  k3s_minor = "k3s --version | sed -n 's/^k3s version v\\([0-9]*\\.[0-9]*\\).*/\\1/p'"
  k3s_fits  = "case ' ${join(" ", var.k3s_minors)} ' in *\" $(${local.k3s_minor}) \"*) ;; *) false;; esac"

  # k3s listens on 6443 before its API can answer.
  wait_api = "for _ in $(seq 60); do k3s kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 5; done"

  # The names Flux's own Secret reference expects in each kind of secret. The
  # identity and the password are the parts that have to stay out of state.
  # They go into the Secret byte for byte, so a newline added here would become
  # part of the user name Flux sends.
  git_files_plain = var.git_auth == "ssh" ? { known_hosts = var.git_known_hosts } : var.git_auth == "https" ? merge({ username = var.git_username }, var.git_ca_cert != "" ? { "ca.crt" = var.git_ca_cert } : {}) : {}
  git_files_wo    = var.git_auth == "ssh" ? toset(["identity"]) : var.git_auth == "https" ? toset(["password"]) : toset([])

  sync_content = join("---\n", [
    yamlencode({
      apiVersion = "source.toolkit.fluxcd.io/v1"
      kind       = "GitRepository"
      metadata   = { name = "flux-system", namespace = "flux-system" }
      spec = merge({
        interval = var.interval
        url      = var.git_url
        ref      = { branch = var.git_branch }
      }, var.git_auth == "none" ? {} : { secretRef = { name = "flux-system" } })
    }),
    yamlencode({
      apiVersion = "kustomize.toolkit.fluxcd.io/v1"
      kind       = "Kustomization"
      metadata   = { name = "flux-system", namespace = "flux-system" }
      spec = {
        interval  = var.interval
        path      = var.git_path
        prune     = var.prune
        sourceRef = { kind = "GitRepository", name = "flux-system" }
      }
    }),
  ])
}

circuit "flux" {
  hosts = { server = var.server }

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Flux only supports the three newest Kubernetes minors, and on anything
  # older the controllers can fail well after the install has gone through.
  step "k3s_version" {
    command {
      command = "${local.k3s_fits} || { echo \"k3s $(${local.k3s_minor}) is not on k3s_minors (${join(", ", var.k3s_minors)}), the versions Flux ${var.flux_version} supports. Set k3s_version and checksums on circuit-k3s to a supported release.\" >&2; exit 1; }"
      unless  = local.k3s_fits
    }
  }

  step "dir" {
    directory {
      path = local.dir
    }
  }

  # Every controller, CRD and policy of a Flux release in one file, the same
  # for every architecture, so there's no CLI to download on the host.
  step "manifest" {
    download {
      url    = "https://github.com/fluxcd/flux2/releases/download/${var.flux_version}/install.yaml"
      sha256 = var.install_sha256
      dest   = local.install
    }
  }

  # Server-side, since Flux's CRDs are too big for the annotation a client-side
  # apply keeps. On a change of version, this is the upgrade too.
  step "install" {
    command {
      command  = "${local.wait_api}; k3s kubectl apply --server-side --force-conflicts --field-manager=conn3x -f ${local.install} >/dev/null && k3s kubectl -n flux-system rollout status deploy --timeout=10m"
      triggers = { manifest = conn3x_download.flux__manifest[each.key].revision }
    }
  }

  step "etc" {
    directory {
      path = local.etc
      mode = "0700"
    }
  }

  step "git_dir" {
    directory {
      path = local.git_dir
      mode = "0700"
    }
  }

  step "git_plain" {
    for_each = local.git_files_plain
    file {
      path      = "${local.git_dir}/${item.key}"
      content   = item.value
      mode      = "0600"
      on_remove = "delete"
    }
  }

  step "git_secret_file" {
    for_each = local.git_files_wo
    file {
      path       = "${local.git_dir}/${item.value}"
      content_wo = var.git_auth == "ssh" ? var.git_ssh_private_key : var.git_password
      on_remove  = "delete"
    }
  }

  # The Secret is built from files on the host, so the key or password never
  # passes through a command line, a plan or state.
  step "git_secret" {
    command {
      command = var.git_auth == "none" ? "k3s kubectl -n flux-system delete secret flux-system --ignore-not-found" : "k3s kubectl -n flux-system create secret generic flux-system --from-file=${local.git_dir} --dry-run=client -o yaml | k3s kubectl apply -f - >/dev/null"
      triggers = {
        auth    = var.git_auth
        install = conn3x_command.flux__install[each.key].revision
        plain   = join(",", [for f in conn3x_file.flux__git_plain : f.revision])
        secret  = join(",", [for f in conn3x_file.flux__git_secret_file : f.revision])
      }
    }
  }

  step "sync_file" {
    file {
      path    = local.sync
      mode    = "0600"
      content = local.sync_content
    }
  }

  # Flux only notices a changed Secret at its next interval, and until then the
  # old Ready condition still stands. So this asks for a reconcile and waits
  # for it, which means a wrong URL, a refused key or a broken manifest fails
  # this apply, rather than sitting in a status nobody has looked at yet.
  step "sync" {
    command {
      command = "k3s kubectl apply -f ${local.sync} >/dev/null && t=$(date +%s) && k3s kubectl -n flux-system annotate --overwrite gitrepository/flux-system kustomization/flux-system reconcile.fluxcd.io/requestedAt=$t >/dev/null && k3s kubectl -n flux-system wait gitrepository/flux-system kustomization/flux-system --for=jsonpath='{.status.lastHandledReconcileAt}'=$t --timeout=5m && k3s kubectl -n flux-system wait gitrepository/flux-system kustomization/flux-system --for=condition=Ready --timeout=5m || { k3s kubectl -n flux-system get gitrepository,kustomization >&2; exit 1; }"
      triggers = {
        sync   = conn3x_file.flux__sync_file[each.key].revision
        secret = conn3x_command.flux__git_secret[each.key].revision
      }
    }
  }
}
