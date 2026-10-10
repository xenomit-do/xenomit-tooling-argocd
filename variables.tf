variable "argocd_server" {
  description = "In-cluster ArgoCD API endpoint."
  type        = string
  default     = "argocd-server.argocd.svc.cluster.local:80"
}

variable "argocd_auth_token" {
  description = "Scoped xenomit-tofu API token supplied by Atlantis."
  type        = string
  sensitive   = true
}

variable "repository_url" {
  description = "Private Gitea repository URL readable by ArgoCD."
  type        = string
  default     = "http://gitea.git.svc.cluster.local:3000/xenomit/xenomit-platform-argocd"
}

variable "cluster_server" {
  description = "In-cluster Kubernetes API server."
  type        = string
  default     = "https://kubernetes.default.svc"
}