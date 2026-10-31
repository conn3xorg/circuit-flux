variable "server" {
  type        = any
  description = "One k3s server to run kubectl on: an address, or a host object with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "git_url" {
  type        = string
  description = "Git repository Flux watches, as an ssh://, https:// or http:// URL. This goes into state, so credentials belong in git_ssh_private_key or git_password."

  validation {
    condition     = can(regex("^(ssh|https?)://", var.git_url)) && !can(regex("^https?://[^/]*@", var.git_url)) && !can(regex("^ssh://[^/@]*:[^/@]*@", var.git_url))
    error_message = "git_url must start with ssh://, https:// or http://, with no password in it. For scp-style addresses, git@host:org/repo.git becomes ssh://git@host/org/repo.git."
  }
}

variable "git_branch" {
  type        = string
  default     = "main"
  description = "Branch to follow."
}

variable "git_path" {
  type        = string
  default     = "./"
  description = "Directory in the repository to reconcile, relative to its root."

  validation {
    condition     = can(regex("^\\./", var.git_path)) && !can(regex("\\.\\.", var.git_path))
    error_message = "git_path starts with ./ and stays inside the repository, such as \"./clusters/home\"."
  }
}

variable "git_auth" {
  type        = string
  default     = "none"
  description = "How Flux logs in to the repository: \"none\", \"ssh\" (git_ssh_private_key and git_known_hosts) or \"https\" (git_username and git_password)."

  validation {
    condition     = contains(["none", "ssh", "https"], var.git_auth)
    error_message = "git_auth is \"none\", \"ssh\" or \"https\"."
  }

  validation {
    condition     = var.git_auth == "none" || can(regex(var.git_auth == "ssh" ? "^ssh://" : "^https?://", var.git_url))
    error_message = "git_auth = \"ssh\" needs an ssh:// URL, and git_auth = \"https\" needs an https:// or http:// URL."
  }
}

variable "git_ssh_private_key" {
  type        = string
  default     = null
  ephemeral   = true
  description = "Private key Flux logs in with, in PEM or OpenSSH form, for git_auth = \"ssh\". Never reaches state."
}

variable "git_known_hosts" {
  type        = string
  default     = ""
  description = "known_hosts lines for the Git server, for git_auth = \"ssh\", such as the output of ssh-keyscan. Flux refuses SSH without them."

  validation {
    condition     = var.git_auth != "ssh" || length(trimspace(var.git_known_hosts)) > 0
    error_message = "git_auth = \"ssh\" needs git_known_hosts."
  }
}

variable "git_username" {
  type        = string
  default     = "git"
  description = "User name for git_auth = \"https\". Many Git hosts take anything here when the password is a token."
}

variable "git_password" {
  type        = string
  default     = null
  ephemeral   = true
  description = "Password or token for git_auth = \"https\". Never reaches state."
}

variable "git_ca_cert" {
  type        = string
  default     = ""
  description = "PEM certificate of the CA that signed the Git server's certificate, for git_auth = \"https\" against a private CA."
}

variable "interval" {
  type        = string
  default     = "1m"
  description = "How often Flux checks the repository and reconciles it, as a Go duration such as \"1m\" or \"1h\"."

  validation {
    condition     = can(regex("^([0-9]+(s|m|h))+$", var.interval))
    error_message = "interval is a duration such as \"30s\", \"5m\" or \"1h\"."
  }
}

variable "prune" {
  type        = bool
  default     = true
  description = "Delete from the cluster what has been deleted from the repository."
}

variable "flux_version" {
  type        = string
  default     = "v2.10.0"
  description = "Flux release to install, from https://github.com/fluxcd/flux2/releases. Change it with install_sha256 and k3s_minors."

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_version))
    error_message = "flux_version is a release tag such as \"v2.10.0\"."
  }
}

variable "install_sha256" {
  type        = string
  default     = "a8c838ccd9be5d30eba9df87cd229b7c4eb80c0049fba1bc3b9840829f267f28"
  description = "SHA-256 of the release's install.yaml."

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.install_sha256))
    error_message = "install_sha256 is a SHA-256 in lowercase hex."
  }
}

variable "k3s_minors" {
  type        = list(string)
  default     = ["1.35", "1.36", "1.37"]
  description = "Kubernetes minor versions the server's k3s may run, from the release notes of flux_version. Anything else fails the apply before Flux is touched."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
