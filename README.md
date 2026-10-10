# xenomit-platform-argocd

OpenTofu-managed ArgoCD configuration for the self-hosted Gitea Actions runner. Atlantis runs OpenTofu in-cluster; no hosted IaC runner or GitHub repository is used.

This stack manages the `xenomit-platform-runners` AppProject and `xenomit-actions-runner` Application. The Application adopts the existing runner Deployment, ConfigMaps, and PVCs in namespace `ci`, and tracks this repository's `main` branch at `deploy/runner`. ArgoCD will show the runner resources under the dedicated project and Application after the pull request is applied and merged.

## Pull request flow

Atlantis automatically plans OpenTofu changes for pull requests. Review its plan comment, then reply `atlantis apply` when ready. With `automerge: true`, Atlantis merges after all plans for the pull request have applied successfully.

The runner Application tracks main so Atlantis can apply and merge the PR without waiting for runner resources from the unmerged PR head.

## State and credentials

OpenTofu state is stored in the Kubernetes backend in namespace `atlantis-state`, using a separate suffix for this repository. Atlantis receives a one-year token for the existing `xenomit-tofu` ArgoCD account. That account can read ArgoCD resources and create/update only the runner AppProject and Application. The token is stored in Kubernetes Secret `ci/atlantis-iac`, not in Git.

ArgoCD reads this private repository through the existing Gitea repository credential template. The repository remains under the `xenomit` organization and accessible to its Owners team.

OpenTofu 1.12.6 is pinned in `atlantis.yaml`.