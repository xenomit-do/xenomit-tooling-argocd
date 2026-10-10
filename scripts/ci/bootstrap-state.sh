#!/usr/bin/env bash
set -euo pipefail
: "${GITEA_PROVIDER_TOKEN:?missing GITEA_PROVIDER_TOKEN}"
: "${GITEA_OWNER:?missing GITEA_OWNER}"
state_addresses="$(tofu state list 2>/dev/null || true)"
for repository in xenomit-platform-gitea xenomit-platform-argocd; do
  address="gitea_repository.managed["$repository"]"
  if printf '%s\n' "$state_addresses" | grep --fixed-strings --line-regexp --quiet "$address"; then continue; fi
  response="$(mktemp)"
  code="$(curl --silent --show-error --location --header "Authorization: token $GITEA_PROVIDER_TOKEN" --output "$response" --write-out '%{http_code}' "$GITEA_BASE_URL/api/v1/repos/$GITEA_OWNER/$repository")"
  if [[ "$code" != "200" ]]; then
    echo "Cannot import $repository: Gitea returned HTTP $code. Create both private repository shells under gitops and push their main branches first." >&2
    cat "$response" >&2
    rm -f "$response"
    exit 1
  fi
  repository_id="$(jq -er '.id' "$response")"
  rm -f "$response"
  echo "Importing $repository (Gitea id $repository_id)."
  tofu import -input=false -no-color "$address" "$repository_id"
  state_addresses="$(tofu state list)"
done
