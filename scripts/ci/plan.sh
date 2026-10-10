#!/usr/bin/env bash
set -euo pipefail
: "${PR_HEAD_SHA:?missing PR_HEAD_SHA}"
: "${PR_NUMBER:?missing PR_NUMBER}"
source scripts/ci/package-state.sh
trap release_lock EXIT
acquire_lock "$PR_HEAD_SHA"
tofu init -input=false -no-color
load_state
if [[ "$PROJECT_KEY" == "gitea" && "$STATE_GENERATION" == "none" ]]; then
  bash scripts/ci/bootstrap-state.sh
  store_state
fi
PLAN_FILE="$RUNNER_TEMP/$PROJECT_KEY-$PR_HEAD_SHA.tfplan"
tofu plan -input=false -no-color -out="$PLAN_FILE"
publish_plan "$PLAN_FILE" "$PR_HEAD_SHA"
SUMMARY_FILE="${GITEA_STEP_SUMMARY:-${GITHUB_STEP_SUMMARY:-/dev/null}}"
{
  echo "## OpenTofu plan"
  echo
  echo "- Stack: $PROJECT_KEY"
  echo "- PR head: $PR_HEAD_SHA"
  echo "- State generation: $STATE_GENERATION"
  echo
  echo "To apply this exact plan and merge the unchanged PR head, comment:"
  echo
  echo "    /tofu apply"
} >> "$SUMMARY_FILE"
echo "Encrypted plan published for PR $PR_NUMBER at $PR_HEAD_SHA."
