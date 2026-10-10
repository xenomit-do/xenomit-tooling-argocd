#!/usr/bin/env bash
set -euo pipefail
: "${GITEA_BASE_URL:?missing GITEA_BASE_URL}"
: "${GITEA_OWNER:?missing GITEA_OWNER}"
: "${GITEA_PACKAGE_USER:?missing GITEA_PACKAGE_USER}"
: "${GITEA_PACKAGE_TOKEN:?missing GITEA_PACKAGE_TOKEN}"
: "${STATE_PACKAGE:?missing STATE_PACKAGE}"
: "${PLAN_PACKAGE:?missing PLAN_PACKAGE}"
: "${LOCK_PACKAGE:?missing LOCK_PACKAGE}"
CI_SCRIPTS_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
STATE_TMP_DIR="$RUNNER_TEMP/tofu-state"
mkdir -p "$STATE_TMP_DIR"
LOCK_ACQUIRED=0
state_file() {
  if [[ -n "${TF_STATE_FILE:-}" ]]; then
    printf '%s' "$TF_STATE_FILE"
  else
    printf '%s/terraform.tfstate' "$(pwd)"
  fi
}
package_url() {
  printf '%s/api/packages/%s/generic/%s/%s/%s' "$GITEA_BASE_URL" "$GITEA_OWNER" "$1" "$2" "$3"
}
package_version_url() {
  printf '%s/api/packages/%s/generic/%s/%s' "$GITEA_BASE_URL" "$GITEA_OWNER" "$1" "$2"
}
package_download() {
  local package="$1" version="$2" filename="$3" destination="$4" code
  code="$(curl --silent --show-error --location --user "$GITEA_PACKAGE_USER:$GITEA_PACKAGE_TOKEN" --output "$destination" --write-out '%{http_code}' "$(package_url "$package" "$version" "$filename")")"
  if [[ "$code" == "200" ]]; then return 0; fi
  rm -f "$destination"
  if [[ "$code" == "404" ]]; then return 4; fi
  echo "Package download failed with HTTP $code for $package/$version/$filename." >&2
  return 1
}
package_put() {
  local package="$1" version="$2" filename="$3" source="$4" response code
  response="$(mktemp)"
  code="$(curl --silent --show-error --location --user "$GITEA_PACKAGE_USER:$GITEA_PACKAGE_TOKEN" --upload-file "$source" --output "$response" --write-out '%{http_code}' "$(package_url "$package" "$version" "$filename")")"
  if [[ "$code" == "201" || "$code" == "200" ]]; then rm -f "$response"; return 0; fi
  echo "Package upload failed with HTTP $code for $package/$version/$filename." >&2
  cat "$response" >&2
  rm -f "$response"
  return 1
}
package_delete_version() {
  local package="$1" version="$2" response code
  response="$(mktemp)"
  code="$(curl --silent --show-error --location --user "$GITEA_PACKAGE_USER:$GITEA_PACKAGE_TOKEN" --request DELETE --output "$response" --write-out '%{http_code}' "$(package_version_url "$package" "$version")")"
  if [[ "$code" == "204" || "$code" == "404" ]]; then rm -f "$response"; return 0; fi
  echo "Package delete failed with HTTP $code for $package/$version." >&2
  cat "$response" >&2
  rm -f "$response"
  return 1
}
acquire_lock() {
  local pr_head="$1" lock_file="$STATE_TMP_DIR/lock.json"
  jq -n --arg repository "$GITHUB_REPOSITORY" --arg run_id "$GITHUB_RUN_ID" --arg actor "$GITHUB_ACTOR" --arg pr_number "$PR_NUMBER" --arg head_sha "$pr_head" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{repository:$repository,run_id:$run_id,actor:$actor,pr_number:$pr_number,head_sha:$head_sha,created_at:$created_at}' > "$lock_file"
  if package_put "$LOCK_PACKAGE" active lock.json "$lock_file"; then
    LOCK_ACQUIRED=1
    echo "Acquired the $PROJECT_KEY state lock."
  else
    echo "Could not acquire the state lock. Another plan/apply may be running; if not, check for a stale active lock package." >&2
    return 1
  fi
}
release_lock() {
  if [[ "$LOCK_ACQUIRED" == "1" ]]; then
    package_delete_version "$LOCK_PACKAGE" active
    LOCK_ACQUIRED=0
    echo "Released the $PROJECT_KEY state lock."
  fi
}
load_state() {
  local pointer="$STATE_TMP_DIR/current.json" version target
  target="$(state_file)"
  if package_download "$STATE_PACKAGE" current current.json "$pointer"; then
    version="$(jq -er '.version' "$pointer")"
    package_download "$STATE_PACKAGE" "$version" state.sealed "$STATE_TMP_DIR/state.sealed"
    package_download "$STATE_PACKAGE" "$version" state.hmac "$STATE_TMP_DIR/state.hmac"
    bash "$CI_SCRIPTS_DIR/seal.sh" open "$STATE_TMP_DIR/state.sealed" "$STATE_TMP_DIR/state.hmac" "$target"
    STATE_GENERATION="$version"
    STATE_SHA="$(jq -er '.sha256' "$pointer")"
    echo "Loaded state generation $STATE_GENERATION."
  else
    local result=$?
    if [[ "$result" != "4" ]]; then return "$result"; fi
    STATE_GENERATION="none"
    STATE_SHA="none"
    rm -f "$target"
    echo "No state exists yet."
  fi
}
store_state() {
  local target serial lineage sha version state_meta
  target="$(state_file)"
  [[ -f "$target" ]] || { echo "OpenTofu produced no state file at $target." >&2; return 1; }
  serial="$(jq -er '.serial' "$target")"
  lineage="$(jq -er '.lineage' "$target")"
  sha="$(sha256sum "$target" | awk '{print $1}')"
  if [[ "$sha" == "$STATE_SHA" ]]; then
    echo "State is unchanged; the current generation remains $STATE_GENERATION."
    return 0
  fi
  version="s-$serial-$sha"
  state_meta="$STATE_TMP_DIR/current.json"
  bash "$CI_SCRIPTS_DIR/seal.sh" seal "$target" "$STATE_TMP_DIR/state.sealed" "$STATE_TMP_DIR/state.hmac"
  package_delete_version "$STATE_PACKAGE" "$version"
  package_put "$STATE_PACKAGE" "$version" state.sealed "$STATE_TMP_DIR/state.sealed"
  package_put "$STATE_PACKAGE" "$version" state.hmac "$STATE_TMP_DIR/state.hmac"
  jq -n --arg version "$version" --arg lineage "$lineage" --arg sha256 "$sha" --argjson serial "$serial" '{version:$version,lineage:$lineage,serial:$serial,sha256:$sha256}' > "$state_meta"
  package_delete_version "$STATE_PACKAGE" current
  package_put "$STATE_PACKAGE" current current.json "$state_meta"
  STATE_GENERATION="$version"
  STATE_SHA="$sha"
  echo "Published state generation $STATE_GENERATION."
}
publish_plan() {
  local plan_file="$1" pr_head="$2" metadata="$STATE_TMP_DIR/plan-metadata.json"
  bash "$CI_SCRIPTS_DIR/seal.sh" seal "$plan_file" "$STATE_TMP_DIR/plan.sealed" "$STATE_TMP_DIR/plan.hmac"
  jq -n --arg repository "$GITHUB_REPOSITORY" --arg project "$PROJECT_KEY" --arg pr_number "$PR_NUMBER" --arg head_sha "$pr_head" --arg state_generation "$STATE_GENERATION" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{repository:$repository,project:$project,pr_number:$pr_number,head_sha:$head_sha,state_generation:$state_generation,created_at:$created_at}' > "$metadata"
  package_delete_version "$PLAN_PACKAGE" "$pr_head"
  package_put "$PLAN_PACKAGE" "$pr_head" plan.sealed "$STATE_TMP_DIR/plan.sealed"
  package_put "$PLAN_PACKAGE" "$pr_head" plan.hmac "$STATE_TMP_DIR/plan.hmac"
  package_put "$PLAN_PACKAGE" "$pr_head" metadata.json "$metadata"
}
