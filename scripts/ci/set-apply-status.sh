#!/usr/bin/env bash
set -euo pipefail

COMMIT_SHA="$1"
API_ROOT="$GITEA_BASE_URL/api/v1"
REPOSITORY_NAME="$(printf '%s' "$GITHUB_REPOSITORY" | cut -d/ -f2)"
STATUS_BODY="$(jq -nc '{context:"tofu/apply",state:"success",description:"OpenTofu plan applied"}')"
STATUS_RESPONSE="$RUNNER_TEMP/tofu-apply-status.json"
STATUS_CODE="$(curl --silent --show-error --location --request POST \
  --header "Authorization: token $GITEA_WRITE_TOKEN" \
  --header "Content-Type: application/json" \
  --data "$STATUS_BODY" \
  --output "$STATUS_RESPONSE" --write-out '%{http_code}' \
  "$API_ROOT/repos/$GITEA_OWNER/$REPOSITORY_NAME/statuses/$COMMIT_SHA")"
if [[ "$STATUS_CODE" != "201" ]]; then
  echo "Infrastructure was applied, but Gitea did not record the required tofu/apply commit status (HTTP $STATUS_CODE)." >&2
  cat "$STATUS_RESPONSE" >&2
  exit 1
fi
