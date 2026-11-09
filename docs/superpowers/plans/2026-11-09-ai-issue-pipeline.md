# AI issue pipeline — implementation plan

Design: [../specs/2026-11-09-ai-issue-pipeline-design.md](../specs/2026-11-09-ai-issue-pipeline-design.md)

Order matters: the spike (Task 2) can change how `run-stage.sh` is written, so nothing in
Tasks 6–8 is written before its findings are recorded. Steps marked **[owner]** need bjhara
(account settings, secrets, paid services); everything else Claude can do locally.

---

## Task 1 — Repo skeleton and GitHub repo

1. Add `.gitignore` (Java/Maven `target/`, IDE files, `.env`, `*.env.local`, `.claude/settings.local.json`, `*.pem`, `*.key`).
2. Add a minimal `README.md` stub (title + one-line purpose; filled in Task 9).
3. **[owner, confirm first]** Create public repo `bjhara/experimental-sbx` with `gh repo create --public --source . --push`.
4. **[owner]** Repo settings: enable *Template repository*, *Allow auto-merge*, *Automatically delete head branches*,
   *Secret scanning* + *Push protection*.

Done when: repo exists on GitHub with the design doc and plan on `main`.

## Task 2 — Spike: prove sbx cloud works from GitHub Actions

Throwaway workflow `.github/workflows/spike.yml` (`workflow_dispatch`) on a `spike` branch. Answers design open items 1–7.

1. **[owner]** Create secrets `DOCKER_USER`, `DOCKER_PAT` (Docker PAT with sandbox access),
   `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`), `AI_GITHUB_TOKEN`
   (fine-grained, this repo only: Contents RW, Issues RW, Pull requests RW, Metadata R).
2. Workflow steps, each echoing a clear PASS/FAIL marker:
   - install `sbx` on `ubuntu-latest` (per Docker's Linux install docs) — item 1;
   - `sbx login --password-stdin` — item 1;
   - `sbx --cloud create --cpus 1 --memory 2g --ttl 20m --on-timeout delete claude` (and `shell` as a fallback) — item 2;
   - `exec`: `which claude git gh java mvn`, `cat /etc/os-release` — item 2, 6;
   - env check: does `create -e FOO=1` and/or `exec -e FOO=1` reach the process (print `${FOO:+set}`, never the value) — item 4;
   - network: `curl -sI` github.com, api.github.com, repo.maven.apache.org, api.anthropic.com, deb mirror — item 5;
   - time a JDK 25 + Maven install (apt `openjdk-25-jdk` if available, else Temurin tarball) — item 6;
   - `claude -p "Reply with the word PONG" --dangerously-skip-permissions` with OAuth token env — item 3;
   - `gh api repos/{repo}` with `GH_TOKEN` to confirm token works from inside the sandbox;
   - always: `sbx --cloud rm --force`.
3. Item 7 (admin bypass with PAT) is tested later in Task 10, once the ruleset exists.
4. Record findings in `docs/superpowers/spike-findings.md`; delete `spike.yml` and the branch.

Done when: every item has a recorded answer, and any design deviation is noted in findings
(e.g. image choice, env mechanism, Java install method).

## Task 3 — Demo app

1. `pom.xml`: groupId `com.example`, artifactId `hello`, Java 25 (`maven.compiler.release=25`),
   JUnit Jupiter (latest 5.x), surefire, exec main class `com.example.hello.App`.
2. `Greeter.greet(String name)` → `"Hello, " + name + "!"`; `App.main` prints `Greeter.greet("world")`.
3. `GreeterTest` asserting `"Hello, world!"`.
4. Verify locally: `mvn -B verify` passes (install Maven if missing; Java 25 is present).

## Task 4 — CI workflow

`.github/workflows/ci.yml`, on `pull_request` and `push` to `main`, `permissions: contents: read`.

- Job `build`: checkout (fetch-depth 0), gitleaks (`gitleaks/gitleaks-action` pinned by SHA, or the CLI), `actions/setup-java` (temurin, 25, maven cache), `mvn -B verify`.
- Job `protected-paths`: on PRs, `git diff --name-only origin/$BASE...HEAD`; fail with a clear message if any path matches `^\.ai/` or `^\.github/`. On push, pass trivially.

Verify: open a throwaway PR changing only `src/` → both green; one touching `.ai/` → `protected-paths` red.

## Task 5 — Labels, config, setup script, CODEOWNERS

1. `.ai/create-labels.sh`: idempotent `gh label create --force` for the 7 labels with colors/descriptions.
2. `.ai/config.env`: header comment "NON-SECRET SETTINGS ONLY"; `SBX_CPUS=1`, `SBX_MEMORY=2g`,
   `SBX_AGENT` (from spike), `TTL_PLAN=45m`, `TTL_IMPLEMENT=2h`, `VERIFY_CMD="mvn -B verify"`, `CLAUDE_MODEL=`.
3. `.ai/setup.sh`: idempotent install of JDK 25 + Maven (+ `gh`, `git` if spike showed they're missing),
   using the method found in the spike. Configure `git user.name/email` for commits.
4. `.github/CODEOWNERS`: `/.ai/ @bjhara`, `/.github/ @bjhara`.
5. `.github/ISSUE_TEMPLATE/feature.md`: what / why / acceptance criteria.
6. **[owner]** run `.ai/create-labels.sh` once.

## Task 6 — Shared driver `.ai/run-stage.sh`

`run-stage.sh <plan|implement> <issue>`, `set -euo pipefail`, never `set -x`, sources `config.env`.
Functions:

- `guard`: actor permission via `gh api repos/$REPO/collaborators/$ACTOR/permission` ∈ {admin, maintain, write};
  issue must not have `ai-working`. Otherwise exit 0 with a log line (no labels touched).
- `reset_labels`: remove trigger + `ai-planned ai-questions ai-implemented ai-failed`; add `ai-working`.
- `sbx_login`, `sbx_create` (name `ai-<stage>-<N>-<run_id>`, size/TTL from config, env per spike findings;
  auth: OAuth token if non-empty else API key).
- `sbx_run`: exec clone (token via `gh auth setup-git`/credential helper rather than URL),
  `bash .ai/setup.sh`, then `claude -p` with the context header (repo, issue, stage, run id, run URL, verify cmd)
  prepended to `.ai/prompts/<stage>.md`; stream output.
- `backstop` (via `trap ... EXIT`): if none of `ai-planned ai-questions ai-implemented` present → add `ai-failed`
  and comment with run URL; always remove `ai-working`; always `sbx --cloud rm --force`.

Lint with `shellcheck`.

## Task 7 — Prompts

`.ai/prompts/plan.md` and `.ai/prompts/implement.md` per the design's "Prompt responsibilities" and Security 5–6, 8:
trust rule, marker rule, exact comment headings and hidden markers, allowed labels, no secrets, no `.github/` edits,
how to read the issue (`gh issue view $ISSUE --comments --json title,body,comments,author,authorAssociation`),
what to do when blocked. Keep them self-contained and readable — they are the main thing template users edit.

## Task 8 — Stage workflows

1. `ai-plan.yml` / `ai-implement.yml`: `on: issues: types: [labeled]`, `if: github.event.label.name == 'ai-plan'` (resp.),
   `concurrency: ai-issue-${{ github.event.issue.number }}`, `cancel-in-progress: false`, `timeout-minutes` > TTL,
   `permissions: contents: read`; checkout; run `.ai/run-stage.sh` with secrets as env
   (`GH_TOKEN=${{ secrets.AI_GITHUB_TOKEN }}` for the runner-side `gh` calls too, so labels/comments come from the same identity).
2. `ai-pr-failed.yml`: `on: workflow_run: workflows: [CI], types: [completed]`, if conclusion failure and head branch
   starts with `ai/issue-`; parse N; swap `ai-implemented` → `ai-failed`; comment with the run link and, if
   `protected-paths` failed, a "needs manual review" note.

## Task 9 — README

Purpose; how the flow works (label table + diagram); setup checklist for the owner and for template users
(secrets, labels, repo settings, ruleset click-path, CODEOWNERS); how to edit prompts; adapting to Python/Node
(`setup.sh`, `VERIFY_CMD`, `build` job); security model & **accepted risks** (own account, protected-paths is a speed
bump, read/triage collaborators trusted, prompt injection); costs (micro sandbox, TTLs); troubleshooting.

## Task 10 — Ruleset and end-to-end test

1. **[owner]** Create ruleset on `main`: require PR, required checks `build` + `protected-paths`,
   block force pushes, bypass actor = repository admin.
2. Spike item 7: from a throwaway branch, check whether `gh pr merge --admin` with `AI_GITHUB_TOKEN` bypasses
   the ruleset on a red PR. Record in README.
3. E2E scenarios on real issues:
   - clear issue ("make the greeting configurable via args") → `ai-plan` → plan comment + `ai-planned`
     → `ai-implement` → PR, CI green, auto-merged, issue closed, `ai-implemented`;
   - vague issue → `ai-questions`; answer as owner; re-apply `ai-plan` → revised plan;
   - stranger-style comment with instructions (from a second account if available) → ignored by Claude;
   - issue that requires a `.ai/` change → PR opened, `protected-paths` red, `ai-failed` with manual-review note;
   - forced failure (e.g. TTL 1m) → `ai-failed`, `ai-working` removed, sandbox gone (`sbx --cloud ls`).
4. Fix what breaks; record observations (durations, cost) in README.

## Task 11 — Template polish

- Scan the repo for hard-coded `bjhara`/repo names; keep only in CODEOWNERS and README, documented as "replace me".
- "Use this template" into a scratch repo, follow README from scratch, confirm the flow works there.
