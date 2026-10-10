variable "argocd_server" {
  description = "In-cluster ArgoCD API endpoint."
  type        = string
  default     = "argocd-server.argocd.svc.cluster.local:80"
}

variable "argocd_auth_token" {
  description = "ArgoCD API token supplied by the workflow."
  type        = string
  sensitive   = true
}

variable "repository_url" {
  description = "Private Gitea repository URL readable by ArgoCD."
  type        = string
  default     = "http://gitea.git.svc.cluster.local:3000/gitops/xenomit-platform-argocd"
}

variable "source_revision" {
  description = "Git revision deployed by the runner Application."
  type        = string
  default     = "main"
}

variable "cluster_server" {
  description = "In-cluster Kubernetes API server."
  type        = string
  default     = "https://kubernetes.default.svc"
}
