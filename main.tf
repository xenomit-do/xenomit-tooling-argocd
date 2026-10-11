terraform {
  # Host bootstrap overrides the connection with -backend-config (see ops/bootstrap.ps1).
  backend "kubernetes" {
    namespace         = "atlantis-state"
    secret_suffix     = "xenomit-platform-argocd"
    in_cluster_config = true
  }
}

provider "argocd" {
  server_addr = var.argocd_server
  auth_token  = var.argocd_auth_token
  plain_text  = true
  grpc_web    = true
}

resource "argocd_project" "runner" {
  metadata {
    name      = "xenomit-platform-runners"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/part-of" = "xenomit"
    }
  }

  spec {
    description = "Self-hosted Gitea Actions runners managed by xenomit-platform-argocd."
    source_repos = [var.repository_url]

    destination {
      server    = var.cluster_server
      namespace = "ci"
    }

    namespace_resource_whitelist {
      group = "apps"
      kind  = "Deployment"
    }

    namespace_resource_whitelist {
      group = ""
      kind  = "ConfigMap"
    }

    namespace_resource_whitelist {
      group = ""
      kind  = "PersistentVolumeClaim"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "argocd_application" "runner" {
  metadata {
    name      = "xenomit-actions-runner"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/part-of" = "xenomit"
    }
  }

  cascade = false
  wait    = false

  spec {
    project = argocd_project.runner.metadata[0].name

    destination {
      server    = var.cluster_server
      namespace = "ci"
    }

    source {
      repo_url        = var.repository_url
      path            = "deploy/runner"
      target_revision = "main"
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
      sync_options = ["PruneLast=true"]
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}