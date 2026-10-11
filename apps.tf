# Argo CD applications that make the platform components visible in the UI.
#
# These objects are created by OpenTofu (the xenomit-platform stack and the bootstrap),
# not by Argo CD, so the applications below are for visibility: no automated sync, nothing
# is pruned or deleted. Argo CD compares what is in git with what runs in the cluster and
# shows Healthy / Synced / OutOfSync for each part, like it did before the OpenTofu setup.
# They belong to the existing AppProject "xenomit" (created by the xenomit-platform stack).

variable "git_base" {
  description = "In-cluster Gitea origin."
  type        = string
  default     = "http://gitea.git.svc.cluster.local:3000"
}

locals {
  platform_repo = "${var.git_base}/xenomit/xenomit-platform.git"

  # name => where its manifests are, which files, and which namespace Argo shows it under.
  platform_views = {
    "xenomit-platform" = {
      description = "Platform baseline: Vault service, default-deny and allow NetworkPolicies, default ServiceAccounts, resource limits."
      path        = "manifests/platform"
      include     = "{05-vault-service,10-network-default-deny,11-bots-allow-infra,13-data-allow,15-default-serviceaccounts,20-resource-limits}.yaml"
      namespace   = "xenomit-system"
    }
    "xenomit-postgres" = {
      description = "PostgreSQL in xenomit-data."
      path        = "manifests/platform"
      include     = "30-postgres.yaml"
      namespace   = "xenomit-data"
    }
    "xenomit-otel" = {
      description = "OpenTelemetry collector in observability."
      path        = "manifests/platform"
      include     = "40-otel-collector.yaml"
      namespace   = "observability"
    }
    "xenomit-openobserve" = {
      description = "OpenObserve in observability."
      path        = "manifests/platform"
      include     = "50-openobserve.yaml"
      namespace   = "observability"
    }
    "xenomit-gitea" = {
      description = "Gitea in namespace git."
      path        = "ops/argocd"
      include     = "gitea.yaml"
      namespace   = "git"
    }
    "xenomit-policies" = {
      description = "Kyverno policies: pod security baseline, required labels and resources, signed images."
      path        = "manifests/policies"
      include     = "*.yaml"
      namespace   = "kyverno"
    }
  }
}

resource "argocd_application" "platform_view" {
  for_each = local.platform_views

  metadata {
    name      = each.key
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/part-of" = "xenomit"
      "xenomit.io/view-only"      = "true"
    }
    annotations = {
      "xenomit.io/description" = each.value.description
    }
  }

  cascade = false
  wait    = false

  spec {
    project = "xenomit"

    destination {
      server    = var.cluster_server
      namespace = each.value.namespace
    }

    source {
      repo_url        = local.platform_repo
      path            = each.value.path
      target_revision = "main"
      directory {
        recurse = false
        include = each.value.include
      }
    }

    revision_history_limit = 5

    # No automated sync, and never prune or delete: OpenTofu owns these objects.
    sync_policy {
      sync_options = ["Prune=false", "Delete=false"]
    }
  }
}
