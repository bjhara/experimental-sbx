#!/usr/bin/env bash
# Runs on the GitHub Actions runner. Starts a cloud sandbox and lets Claude work on an issue.
#
# Usage: .ai/run-stage.sh <plan|implement> <issue-number>
#
# Required env (from the workflow):
#   REPO, ACTOR, RUN_ID, RUN_URL
#   GH_TOKEN                 fine-grained PAT (AI_GITHUB_TOKEN); used here and inside the sandbox
#   DOCKER_USER, DOCKER_PAT  Docker account for sbx
#   CLAUDE_CODE_OAUTH_TOKEN  Claude subscription token, or
#   ANTHROPIC_API_KEY        Anthropic API key (used only if the OAuth token is empty)
#
# Never enable `set -x` in this script: it would print credentials.
set -euo pipefail

STAGE="${1:?stage (plan|implement) required}"
ISSUE="${2:?issue number required}"
case "$STAGE" in
  plan) TRIGGER=ai-plan ;;
  implement) TRIGGER=ai-implement ;;
  *) echo "unknown stage: $STAGE" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

OUTCOME_LABELS=(ai-planned ai-questions ai-implemented)
SBX_NAME="ai-${STAGE}-${ISSUE}-${RUN_ID}"
SANDBOX_CREATED=false

log() { echo "::notice::$*"; }

issue_labels() { gh issue view "$ISSUE" -R "$REPO" --json labels --jq '.labels[].name'; }

guard() {
  local perm
  perm=$(gh api "repos/$REPO/collaborators/$ACTOR/permission" --jq .permission 2>/dev/null || echo none)
  case "$perm" in
    admin|maintain|write) ;;
    *) log "Ignoring: $ACTOR has '$perm' permission (needs write or higher)."; exit 0 ;;
  esac
  if issue_labels | grep -qx ai-working; then
    log "Ignoring: issue #$ISSUE already has ai-working (a run is in progress)."
    exit 0
  fi
}

reset_labels() {
  gh issue edit "$ISSUE" -R "$REPO" \
    --remove-label "$TRIGGER,ai-planned,ai-questions,ai-implemented,ai-failed" \
    --add-label ai-working >/dev/null
}

backstop() {
  local status=$?
  set +e
  local labels
  labels=$(issue_labels)
  local outcome=false
  for l in "${OUTCOME_LABELS[@]}"; do
    grep -qx "$l" <<<"$labels" && outcome=true
  done
  if [ "$outcome" = false ]; then
    gh issue edit "$ISSUE" -R "$REPO" --add-label ai-failed >/dev/null
    gh issue comment "$ISSUE" -R "$REPO" --body "### 🤖 Run failed
The \`$STAGE\` run ended without a result (exit code $status). See the [Action run]($RUN_URL).
<!-- ai-pipeline:failed run=$RUN_ID -->" >/dev/null
  fi
  gh issue edit "$ISSUE" -R "$REPO" --remove-label ai-working >/dev/null
  if [ "$SANDBOX_CREATED" = true ]; then
    sbx --cloud rm --force "$SBX_NAME" || true
  fi
}

install_sbx() {
  if ! command -v sbx >/dev/null; then
    curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh >/dev/null
    sudo apt-get install -y -qq docker-sbx >/dev/null
  fi
  sbx version | head -1
  echo "$DOCKER_PAT" | sbx login --username "$DOCKER_USER" --password-stdin
}

create_sandbox() {
  local ttl
  if [ "$STAGE" = plan ]; then ttl="$TTL_PLAN"; else ttl="$TTL_IMPLEMENT"; fi

  # Bare `-e NAME` copies the value from this environment; values never appear on the command line.
  local env_args=(-e GH_TOKEN -e REPO -e ISSUE -e STAGE -e RUN_ID -e RUN_URL -e VERIFY_CMD -e CLAUDE_MODEL)
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    env_args+=(-e CLAUDE_CODE_OAUTH_TOKEN)
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    env_args+=(-e ANTHROPIC_API_KEY)
  else
    echo "::error::Set the CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY secret." >&2
    exit 1
  fi

  export ISSUE STAGE VERIFY_CMD CLAUDE_MODEL
  SANDBOX_CREATED=true
  sbx --cloud create --no-progress --name "$SBX_NAME" \
    --cpus "$SBX_CPUS" --memory "$SBX_MEMORY" \
    --ttl "$ttl" --on-timeout delete \
    --allow-network "$SBX_ALLOW_NETWORK" \
    "${env_args[@]}" \
    "$SBX_AGENT"
}

run_in_sandbox() {
  # Clone with gh (uses GH_TOKEN from the env; no token in the remote URL), then hand over
  # to the in-sandbox script from the freshly cloned default branch.
  sbx --cloud exec "$SBX_NAME" bash -lc \
    'set -e; cd ~/workspace; gh repo clone "$REPO" repo -- -q; cd repo; gh auth setup-git'
  sbx --cloud exec "$SBX_NAME" bash -lc 'bash ~/workspace/repo/.ai/sandbox-run.sh'
}

guard
reset_labels
trap backstop EXIT
install_sbx
create_sandbox
run_in_sandbox
