# AI issue pipeline with Docker Sandboxes — design

Date: 2026-11-09
Owner: bjhara (GitHub)

## Intent

An experiment in combining **Docker Cloud Sandboxes (`sbx`)** with **GitHub issues** so that
Claude can plan and implement issues automatically, with a human deciding when each stage runs.
The repo is public so anyone can file issues, and it should end up usable as a **template**
for other projects (primarily Java/Maven, but Python and Node.js should be easy).

## Goals

- Label-driven, two-stage flow on GitHub issues: plan, then implement.
- Each stage runs Claude Code headless inside a fresh **micro** cloud sandbox (1 vCPU, 2 GiB).
- Claude can ask questions on the issue; humans answer in comments; humans resume by re-applying a label.
- Implementation ends with a PR that auto-merges **only if required checks pass**.
- Stage instructions are easy to edit: plain Markdown prompt files.
- Repo works as a GitHub template repository; adapting to another stack means editing a setup
  script, a verify command, and the CI workflow.
- Switching Claude auth between subscription token and API key is a secret change, not a code change.
- **The repo contains no secrets whatsoever.**

## Non-goals

- No automatic triggering on issue creation or on comments. **Only label application starts a run.**
- No separate bot account (Claude acts as the owner's account, see Security).
- No custom sandbox image initially (tools installed at runtime by a setup script).
- No multi-issue orchestration, scheduling, or priority handling.

## Anti-goals (failure even if it "works")

- A stranger can trigger a run, or a stranger's comment is treated as an authoritative answer.
- A PR auto-merges with failing checks.
- A PR touching `.ai/` or `.github/` auto-merges.
- A secret is committed to the repo.
- Changing the prompts requires touching workflow YAML or scripts.

## Approaches considered

**A. Claude does all GitHub work itself (chosen).** Sandbox receives a GitHub token; Claude
clones, comments, edits labels, pushes a branch, and opens/auto-merges the PR via `gh`. Least
code, most flexible. Risk: prompt injection via issue text acts with that token, and label/PR
behavior depends on Claude following instructions. Mitigated as far as practical below.

**B. Claude only thinks/codes; the workflow does GitHub writes.** Sandbox has no token; results
come back via `sbx cp`, workflow posts/pushes deterministically. Safer, ~100–150 more lines of bash.
Not chosen: owner preferred A's simplicity for the experiment.

**Rejected: `anthropics/claude-code-action`.** Runs Claude on the runner itself, defeating the
purpose (sandboxing).

**Identity — own account vs bot account.** A bot account would make code-owner review a real,
GitHub-enforced gate and make Claude's actions distinguishable. Owner chose **own account, accept
the risk**: the protected-paths check below is a speed bump, not a lock, and this is documented.

## Label state machine

| Label | Set by | Meaning |
|---|---|---|
| `ai-plan` | human | Start/restart planning. Removed by workflow immediately. |
| `ai-implement` | human | Start/continue implementation. Removed by workflow immediately. |
| `ai-working` | workflow | A sandbox is running for this issue. |
| `ai-questions` | Claude | Questions posted; waiting for answers. Human re-applies `ai-plan` or `ai-implement` to continue. |
| `ai-planned` | Claude | Plan posted as a comment. |
| `ai-implemented` | Claude | PR opened with auto-merge enabled (or awaiting owner merge if protected paths touched). |
| `ai-failed` | workflow | Run crashed/timed out, Claude ended without an outcome label, or PR checks failed. Comment links the run. |

```
[issue] --human: ai-plan--> ai-working --> ai-planned | ai-questions | ai-failed
ai-questions --(answers in comments)--> human: ai-plan again
ai-planned --human: ai-implement--> ai-working --> ai-implemented | ai-questions | ai-failed
ai-implemented --> PR checks pass --> auto-merge --> issue closed via "Closes #N"
                  PR checks fail  --> ai-failed on issue, PR left open
```

**Start of every run:** remove the trigger label and all outcome labels
(`ai-planned`, `ai-questions`, `ai-implemented`, `ai-failed`), then add `ai-working`.
So "outcome label present at end" means "set by this run", and the backstop is a simple label check.
Implementation locates the plan by comment, not by label.

## Security model

Claude runs as the owner's account (`bjhara`) via a fine-grained PAT. Consequences accepted:
Claude can technically do what its token permits, including steps the prompts forbid.
Guardrails:

1. **Fine-grained PAT** (`AI_GITHUB_TOKEN`), single repo only: Contents RW, Issues RW,
   Pull requests RW, Metadata R. **No Workflows, no Administration.** Claude cannot push changes
   under `.github/workflows/` nor change repo settings/rulesets.
2. **Ruleset on `main`**: PR required; required checks `build` and `protected-paths`;
   no direct pushes; no force pushes. **Owner (admin) is the bypass actor** so they can merge
   protected-path PRs manually after review. Auto-merge enabled in repo settings.
   Claude uses `gh pr merge --auto --squash`. (Spike: check whether the PAT without Administration
   can use admin bypass; record result in README. Either way risk is accepted.)
3. **`protected-paths` check** (in `ci.yml`): fails if the PR diff touches `.ai/**` or `.github/**`,
   so auto-merge never fires for those; owner reviews and merges manually. `CODEOWNERS` lists
   `@bjhara` for those paths for visibility (cannot be a required review since PRs are authored by the owner).
4. **Trigger guard**: workflow ignores the label event unless (a) the actor has write/maintain/admin
   permission, and (b) the issue does **not** already carry `ai-working`. (b) stops Claude
   re-triggering itself mid-run by adding a trigger label.
5. **Comment trust rule** (in prompts): only comments whose author association is
   `OWNER` / `MEMBER` / `COLLABORATOR` count as answers or instructions; all others are context
   only. Known gap: read/triage-level collaborators also count — acceptable, documented.
6. **Claude's own comments are marked**: every comment Claude posts starts with a heading
   (`### 🤖 Plan`, `### 🤖 Questions`, `### 🤖 Implemented`) and contains a hidden marker
   `<!-- ai-pipeline:<kind> run=<run_id> -->`. Since Claude and the owner share an account,
   prompts tell Claude: owner-authored comments *with* a marker are Claude's own output;
   owner-authored comments *without* a marker are human answers. The implement stage uses the
   latest owner-authored comment containing `<!-- ai-pipeline:plan`.
7. **Workflow backstop** (always runs): if no outcome label is present, set `ai-failed` and comment
   with the run URL; remove `ai-working`; `sbx --cloud rm --force` the sandbox.
8. **No secrets in the repo**:
   - All credentials live in GitHub Actions secrets: `DOCKER_USER`, `DOCKER_PAT`,
     `AI_GITHUB_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`.
   - Passed to the sandbox only as env vars at runtime; never written to files in the workspace;
     scripts never `echo` them (`set +x` around credential use; rely on Actions masking).
   - `.gitignore` covers `.env`, `*.env.local`, `.claude/settings.local.json`, etc.
     (`.ai/config.env` holds non-secret settings only and says so in a header comment).
   - GitHub secret scanning + push protection enabled (README setup step).
   - `ci.yml` runs gitleaks; a finding fails the `build` check.
   - Prompts instruct Claude never to print env vars or commit credentials.

## Architecture

### Repository layout

```
.github/
  workflows/
    ai-plan.yml          # on: issues [labeled], if label == ai-plan → .ai/run-stage.sh plan
    ai-implement.yml     # on: issues [labeled], if label == ai-implement → .ai/run-stage.sh implement
    ci.yml               # on: pull_request + push main; jobs: build (gitleaks + mvn -B verify), protected-paths
    ai-pr-failed.yml     # on: workflow_run(ci) completed+failure on ai/issue-* → ai-failed + comment on issue
  CODEOWNERS             # .ai/ and .github/ → @bjhara
  ISSUE_TEMPLATE/feature.md
.ai/
  prompts/
    plan.md              # planning instructions (edit freely)
    implement.md         # implementation instructions (edit freely)
  setup.sh               # runs inside sandbox before Claude: install JDK 25 + Maven (+ gh if missing)
  config.env             # NON-SECRET: SBX_CPUS=1 SBX_MEMORY=2g TTL_PLAN=45m TTL_IMPLEMENT=2h VERIFY_CMD="mvn -B verify" CLAUDE_MODEL=
  run-stage.sh           # shared driver for both stages
  create-labels.sh       # one-off: creates labels with gh
src/main/java/com/example/hello/{App,Greeter}.java
src/test/java/com/example/hello/GreeterTest.java
pom.xml                  # Java 25, JUnit 5
.gitignore
README.md                # purpose, setup, adapting as template, security model & accepted risks
```

### Run sequence (`.ai/run-stage.sh <plan|implement> <issue>`, on `ubuntu-latest`)

1. Workflow `concurrency: ai-issue-<N>` (no cancel). Trigger guard (see Security 4).
2. Label reset (see state machine), add `ai-working`.
3. Install `sbx`; `echo "$DOCKER_PAT" | sbx login --username "$DOCKER_USER" --password-stdin`.
4. `sbx --cloud create --name ai-<stage>-<N>-<run_id> --cpus 1 --memory 2g --ttl <TTL> --on-timeout delete <claude|shell>`
   with env `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` *or* `ANTHROPIC_API_KEY`, `REPO`, `ISSUE`, `STAGE`, `RUN_ID`, `RUN_URL`.
5. Via `sbx --cloud exec`: clone repo using `GH_TOKEN` (credential helper, not embedded in remote URL
   saved to disk where avoidable), `bash .ai/setup.sh`, then
   `claude -p "<context header>\n$(cat .ai/prompts/<stage>.md)" --dangerously-skip-permissions [--model]`,
   output streamed to the Action log.
6. Backstop (always): see Security 7.

Prompts contain only instructions; Claude reads the issue itself with
`gh issue view $ISSUE --comments --json ...` (including author association).

### Claude auth switching

If secret `CLAUDE_CODE_OAUTH_TOKEN` is set it is passed; otherwise `ANTHROPIC_API_KEY`.
Switching = add/remove a repo secret. (Spike: whether `sbx --cloud secret set anthropic` proxy
supports OAuth tokens; env var is the baseline.)

### Prompt responsibilities

**plan.md** — read issue + trusted comments, explore the repo, do not change code. Then either post
`### 🤖 Questions` (+ marker) and set `ai-questions`, or post `### 🤖 Plan` (+ marker: summary,
files to touch, steps, test strategy, risks) and set `ai-planned`. Re-plan = new comment; latest wins.

**implement.md** — find latest plan comment (marker) and trusted human answers after it; create or
reuse branch `ai/issue-<N>`; implement; run `$VERIFY_CMD`; commit; push; `gh pr create` (or reuse PR)
with `Closes #N`; `gh pr merge --auto --squash`; comment `### 🤖 Implemented` with PR link; set
`ai-implemented`. If the change must touch `.ai/` or `.github/`, say so in the PR and comment (owner
merges manually). If blocked: `### 🤖 Questions`, set `ai-questions`, push WIP branch if useful.
No plan found: comment and set `ai-failed`.

Both prompts: comment trust rule and marker rule; never print env vars or commit secrets; never add
`ai-plan`/`ai-implement` labels; only touch labels `ai-planned`/`ai-questions`/`ai-implemented`.

### PR check failure → issue

`ai-pr-failed.yml`: on `workflow_run` of `ci.yml` concluding failure on head branch `ai/issue-*`,
parse N, set `ai-failed` (remove `ai-implemented`), comment with link. PR stays open; owner can re-apply
`ai-implement` (Claude reuses branch/PR). A `protected-paths` failure is reported the same way with a
note that it needs manual review rather than a fix.

### Demo app

Maven, Java 25, `com.example.hello.App` prints `Greeter.greet("world")` → "Hello, world!".
One JUnit 5 test for `Greeter`. `ci.yml` uses `actions/setup-java` + `mvn -B verify`.

### Template adaptation (README)

"Use this template" → set the secrets → run `.ai/create-labels.sh` → enable auto-merge, secret
scanning + push protection, and create the `main` ruleset (documented click-path) → replace
`@bjhara` in CODEOWNERS. For Python/Node: edit `.ai/setup.sh`, `VERIFY_CMD`, and the `build` job.

## Constraints

- sbx cloud needs Docker pay-as-you-go; micro = `--cpus 1 --memory 2g`; TTL ≤ 24h; 10 concurrent sandboxes.
- Public repo: issue/comment text is untrusted input to Claude.
- A PAT (not `GITHUB_TOKEN`) is required in the sandbox so Claude's pushes trigger `ci.yml`.

## Open items for the builder (verify in a first spike, before full build)

1. Install `sbx` on `ubuntu-latest` non-interactively; `sbx login` with a PAT.
2. Which cloud image (`claude` vs `shell`) has `claude`, `git`, `gh`; otherwise install in `setup.sh`.
3. `claude -p` headless under `sbx --cloud exec`, with output streamed.
4. Env passing: `create -e` vs `exec -e`.
5. Cloud network policy allows github.com, api.github.com, Maven Central, Anthropic API, apt mirrors.
6. Setup time for JDK + Maven on micro.
7. Whether the fine-grained PAT (no Administration) can use admin ruleset bypass.

## Left to the builder

Exact bash, label colors, comment formatting, issue template wording, README structure.
