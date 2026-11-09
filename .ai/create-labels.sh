#!/usr/bin/env bash
# One-off: create (or update) the pipeline labels. Usage: .ai/create-labels.sh [owner/repo]
set -euo pipefail
repo_args=()
[ $# -ge 1 ] && repo_args=(-R "$1")

label() { gh label create "$1" --color "$2" --description "$3" --force "${repo_args[@]}"; }

label ai-plan        1d76db "Trigger: ask Claude to plan this issue"
label ai-implement   0e8a16 "Trigger: ask Claude to implement the latest plan"
label ai-working     fbca04 "A sandbox is working on this issue"
label ai-questions   d876e3 "Claude has questions; answer, then re-apply the trigger label"
label ai-planned     c5def5 "Claude posted a plan"
label ai-implemented bfdadc "Claude opened a PR"
label ai-failed      b60205 "The run failed; see the linked Action run"
