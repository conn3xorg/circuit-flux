output "flux_version" {
  description = "Flux release installed."
  value       = var.flux_version
}

output "namespace" {
  description = "Namespace Flux and its GitRepository and Kustomization, both named flux-system, are in."
  value       = "flux-system"
}
