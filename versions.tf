terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "= 7.17.1"
    }
  }
}
