#!/usr/bin/env bash
set -euo pipefail
: "${PR_NUMBER:?missing PR_NUMBER}"
: "${GITEA_WRITE_TOKEN:?missing GITEA_WRITE_TOKEN}"
BASE_REPOSITORY="$(git rev-parse --show-toplevel)"
source "$BASE_REPOSITORY/scripts/ci/package-state.sh"
trap release_lock EXIT
API_ROOT="$GITEA_BASE_URL/api/v1"
REPOSITORY_NAME="$(printf '%s' "$GITHUB_REPOSITORY" | cut -d/ -f2)"
PR_JSON="$STATE_TMP_DIR/pull-request.json"
fetch_pr() {
  curl --fail --silent --show-error --location --header "Authorization: token $GITEA_WRITE_TOKEN" "$API_ROOT/repos/$GITEA_OWNER/$REPOSITORY_NAME/pulls/$PR_NUMBER" --output "$PR_JSON"
}
validate_pr() {
  [[ "$(jq -er '.state' "$PR_JSON")" == "open" && "$(jq -er '.base.ref' "$PR_JSON")" == "main" && "$(jq -er '.head.repo.full_name' "$PR_JSON")" == "$GITHUB_REPOSITORY" && "$(jq -er '.user.login' "$PR_JSON")" == "gitops" ]]
}
fetch_pr
PR_HEAD_SHA="$(jq -er '.head.sha' "$PR_JSON")"
if ! validate_pr; then echo "Apply is limited to open, gitops-authored, same-repository PRs targeting main." >&2; exit 1; fi
acquire_lock "$PR_HEAD_SHA"
fetch_pr
if ! validate_pr || [[ "$(jq -er '.head.sha' "$PR_JSON")" != "$PR_HEAD_SHA" ]]; then
  echo "PR changed while acquiring the state lock. Wait for a plan on its current head." >&2
  exit 1
fi
PLAN_META="$STATE_TMP_DIR/plan-metadata.json"
if ! package_download "$PLAN_PACKAGE" "$PR_HEAD_SHA" metadata.json "$PLAN_META"; then
  echo "No successful plan is stored for the current PR head. Wait for its plan run to finish." >&2
  exit 1
fi
if [[ "$(jq -er '.repository' "$PLAN_META")" != "$GITHUB_REPOSITORY" || "$(jq -er '.project' "$PLAN_META")" != "$PROJECT_KEY" || "$(jq -er '.pr_number' "$PLAN_META")" != "$PR_NUMBER" || "$(jq -er '.head_sha' "$PLAN_META")" != "$PR_HEAD_SHA" ]]; then
  echo "Saved plan metadata does not match this PR." >&2
  exit 1
fi
EXPECTED_GENERATION="$(jq -er '.state_generation' "$PLAN_META")"
git fetch --no-tags origin "$PR_HEAD_SHA"
PR_WORKTREE="$RUNNER_TEMP/pr-$GITHUB_RUN_ID"
git worktree add --detach "$PR_WORKTREE" "$PR_HEAD_SHA"
cleanup_worktree() {
  git -C "$BASE_REPOSITORY" worktree remove --force "$PR_WORKTREE" >/dev/null 2>&1 || true
}
trap 'cleanup_worktree; release_lock' EXIT
TF_STATE_FILE="$PR_WORKTREE/terraform.tfstate"
load_state
if [[ "$STATE_GENERATION" != "$EXPECTED_GENERATION" ]]; then
  echo "Saved plan is stale: it used state $EXPECTED_GENERATION, current state is $STATE_GENERATION. Create a new PR head and plan." >&2
  exit 1
fi
package_download "$PLAN_PACKAGE" "$PR_HEAD_SHA" plan.sealed "$STATE_TMP_DIR/plan.sealed"
package_download "$PLAN_PACKAGE" "$PR_HEAD_SHA" plan.hmac "$STATE_TMP_DIR/plan.hmac"
PLAN_FILE="$RUNNER_TEMP/$PROJECT_KEY-$PR_HEAD_SHA.tfplan"
bash "$BASE_REPOSITORY/scripts/ci/seal.sh" open "$STATE_TMP_DIR/plan.sealed" "$STATE_TMP_DIR/plan.hmac" "$PLAN_FILE"
if [[ "$PROJECT_KEY" == "argocd" ]]; then export TF_VAR_source_revision="$PR_HEAD_SHA"; fi
tofu -chdir="$PR_WORKTREE" init -input=false -no-color
tofu -chdir="$PR_WORKTREE" apply -input=false -no-color -auto-approve "$PLAN_FILE"
store_state
fetch_pr
if ! validate_pr || [[ "$(jq -er '.head.sha' "$PR_JSON")" != "$PR_HEAD_SHA" ]]; then
  echo "Infrastructure was applied, but the PR head changed before merge. It was not merged; create a plan for the current head." >&2
  exit 1
fi
bash "$BASE_REPOSITORY/scripts/ci/set-apply-status.sh" "$PR_HEAD_SHA"
MERGE_BODY="$(jq -nc --arg sha "$PR_HEAD_SHA" '{do:"merge",head_commit_id:$sha}')"
MERGE_RESPONSE="$STATE_TMP_DIR/merge-response.json"
MERGE_CODE="$(curl --silent --show-error --location --request POST --header "Authorization: token $GITEA_WRITE_TOKEN" --header "Content-Type: application/json" --data "$MERGE_BODY" --output "$MERGE_RESPONSE" --write-out '%{http_code}' "$API_ROOT/repos/$GITEA_OWNER/$REPOSITORY_NAME/pulls/$PR_NUMBER/merge")"
if [[ "$MERGE_CODE" != "200" ]]; then
  echo "Apply succeeded, but Gitea did not merge the PR (HTTP $MERGE_CODE)." >&2
  cat "$MERGE_RESPONSE" >&2
  exit 1
fi
package_delete_version "$PLAN_PACKAGE" "$PR_HEAD_SHA"
echo "Applied the saved plan and merged PR $PR_NUMBER at $PR_HEAD_SHA."
{
  echo "## OpenTofu apply"
  echo
  echo "Applied state generation $STATE_GENERATION and merged PR $PR_NUMBER at $PR_HEAD_SHA."
} >> "${GITEA_STEP_SUMMARY:-${GITHUB_STEP_SUMMARY:-/dev/null}}"
