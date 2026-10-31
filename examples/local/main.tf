variable "port" {
  type    = number
  default = 2318
}

variable "token" {
  type      = string
  ephemeral = true
  default   = "example-token-change-me"
}

# git.sh writes these two to git.auto.tfvars.
variable "git_host" {
  type    = string
  default = "192.0.2.1"
}

variable "git_known_hosts" {
  type    = string
  default = "192.0.2.1 ssh-ed25519 AAAA"
}

variable "git_ssh_private_key" {
  type      = string
  ephemeral = true
  default   = null
}

module "k3s" {
  source = "github.com/conn3xorg/circuit-k3s?ref=v0.1.3"

  servers = { server1 = "127.0.0.1" }
  token   = var.token

  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}

module "flux" {
  source     = "../.."
  depends_on = [module.k3s]

  server = "127.0.0.1"

  git_url             = "ssh://git@${var.git_host}/srv/git/demo.git"
  git_auth            = "ssh"
  git_ssh_private_key = var.git_ssh_private_key
  git_known_hosts     = var.git_known_hosts
  interval            = "30s"

  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}
