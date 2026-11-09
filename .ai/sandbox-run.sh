#!/usr/bin/env bash
# Runs inside the cloud sandbox, from the cloned repo. Prepares the toolchain and runs Claude
# headless with the stage prompt from .ai/prompts/<stage>.md.
#
# Env (passed in by run-stage.sh): GH_TOKEN, REPO, ISSUE, STAGE, RUN_ID, RUN_URL, VERIFY_CMD,
# CLAUDE_MODEL, and CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY.
# Never enable `set -x` here: it would print credentials.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Commit as the token's account, using its GitHub noreply address.
login=$(gh api user --jq .login)
id=$(gh api user --jq .id)
git config user.name "$login"
git config user.email "${id}+${login}@users.noreply.github.com"

bash .ai/setup.sh

prompt_file=$(mktemp)
{
  cat <<EOF
# Context

- Repository: $REPO
- Issue: #$ISSUE
- Stage: $STAGE
- Run ID: $RUN_ID (use it in the hidden marker of every comment you post)
- Run URL: $RUN_URL
- Your GitHub login (the token's account): $login
- Verify command: $VERIFY_CMD
- Working directory: $(pwd) (a clone of the default branch)

EOF
  cat ".ai/prompts/$STAGE.md"
} >"$prompt_file"

model_args=()
[ -n "${CLAUDE_MODEL:-}" ] && model_args=(--model "$CLAUDE_MODEL")

claude -p "$(cat "$prompt_file")" --dangerously-skip-permissions "${model_args[@]}"
