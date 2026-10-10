# xenomit-platform-argocd

OpenTofu-managed ArgoCD configuration for the self-hosted Gitea Actions runner. OpenTofu itself runs on that runner using the xenomit Gitea Actions label.

This stack manages the ArgoCD AppProject and Application for the existing runner. Applying a PR plan points the Application at that exact PR head; ArgoCD syncs and waits for the runner resources to become healthy before the workflow merges the PR.

The existing ArgoCD controller Helm release is already installed in the cluster and remains managed by the current platform installation. This repository manages ArgoCD's runner project/application and the runner's Kubernetes resources.

## Runner adoption

ArgoCD adopts the existing deployment, two ConfigMaps, and two PVCs in namespace ci. It references the existing xenomit-actions-runner-token Secret without reading or managing its data. PVCs have prune disabled so deleting the ArgoCD Application will not remove runner data.

The runner remains on its existing Gitea Actions label xenomit. The workflow jobs use runs-on: xenomit, so planning and applying happen on the self-hosted runner rather than an external IaC service.

## Gitea setup

Create a private repository named xenomit-platform-argocd under gitops, then push main. The xenomit-platform-gitea stack creates branch protection and manages both platform repository shells.

Set the Gitea repository variable TOFU_GITEA_BASE_URL to the internal origin reachable from runner jobs, without a trailing slash. The current cluster service is http://gitea.git.svc.cluster.local:3000.

Set the repository variable ARGOCD_REPOSITORY_URL to the clone URL ArgoCD can use, for example http://gitea.git.svc.cluster.local:3000/gitops/xenomit-platform-argocd. ArgoCD must already have a repository credential template or repository entry that can read this private Gitea repository.

Create these Actions secrets:

- GITEA_WRITE_TOKEN: repository write/admin token used to publish encrypted state and merge the PR.
- GITEA_PACKAGE_TOKEN: package read/write token for the gitops account.
- TOFU_ARTIFACT_ENCRYPTION_KEY: 64 hexadecimal characters.
- TOFU_ARTIFACT_HMAC_KEY: a different 64 hexadecimal characters.
- ARGOCD_READ_AUTH_TOKEN: read-only ArgoCD token for plan/refresh.
- ARGOCD_WRITE_AUTH_TOKEN: token allowed to create/update the platform project and runner Application.

Generate artifact keys independently with openssl rand -hex 32. The runner job container uses host networking and must resolve argocd-server.argocd.svc.cluster.local:80. The ArgoCD API is configured as plain HTTP inside the cluster.

## Approval flow

A same-repository PR authored by gitops targeting main triggers an OpenTofu plan for its exact head SHA. The plan and state are encrypted and stored as private Gitea generic packages. Reply with the exact comment /tofu apply to apply the saved plan. Apply fails when the PR head or state generation changed, and merges with the expected head SHA only after ArgoCD reports the runner Application healthy.

The lock serializes plans and applies. If a runner is killed and leaves an active lock package, remove that package version only after confirming no job is running. Do not delete state versions. The local OpenTofu state and plan files are excluded from Git.
