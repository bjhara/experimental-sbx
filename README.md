# experimental-sbx

An experiment: GitHub issues are planned and implemented by **Claude Code** running inside
**Docker Cloud Sandboxes** ([`sbx`](https://docs.docker.com/ai/sandboxes/)), driven by labels.
A maintainer decides when each stage runs; Claude does the work in a fresh, disposable
micro sandbox (1 vCPU, 2 GiB) and talks to humans through issue comments.

The repo is also a **template**: click *Use this template* to add the same pipeline to
your own project. The demo app is a tiny Java 25 / Maven "hello, world".

## How it works

```
 you: label ai-plan ─▶ sandbox: Claude reads issue + code ─▶ 🤖 Plan comment      → ai-planned
                                                          └▶ 🤖 Questions comment → ai-questions
 you: answer in a comment, re-apply ai-plan ─▶ revised plan

 you: label ai-implement ─▶ sandbox: Claude branches ai/issue-N, codes, runs mvn verify,
                            opens PR "Closes #N", enables auto-merge → ai-implemented
 CI green ─▶ PR squash-merges, issue closes        CI red ─▶ ai-failed, PR stays open
```

| Label | Set by | Meaning |
|---|---|---|
| `ai-plan` | you | Plan (or re-plan) this issue |
| `ai-implement` | you | Implement the latest plan (or continue after questions) |
| `ai-working` | workflow | A sandbox is running |
| `ai-questions` | Claude | Claude asked something. Answer, then re-apply the trigger label |
| `ai-planned` | Claude | Plan posted |
| `ai-implemented` | Claude | PR opened with auto-merge |
| `ai-failed` | workflow | Run failed or CI failed; the comment links the log |

**Only adding a label starts a run.** Only people with write access can trigger it; labels
added while `ai-working` is present are ignored.

### Files

| Path | What it is |
|---|---|
| [`.ai/prompts/plan.md`](.ai/prompts/plan.md) | Instructions for the planning stage. **Edit freely.** |
| [`.ai/prompts/implement.md`](.ai/prompts/implement.md) | Instructions for the implementation stage. **Edit freely.** |
| [`.ai/config.env`](.ai/config.env) | Non-secret settings: sandbox size, network allow-list, TTLs, verify command, model |
| [`.ai/setup.sh`](.ai/setup.sh) | Installs the toolchain inside the sandbox (JDK 25 + Maven) |
| [`.ai/run-stage.sh`](.ai/run-stage.sh) | Runner-side driver: guard, labels, create sandbox, cleanup |
| [`.ai/sandbox-run.sh`](.ai/sandbox-run.sh) | Sandbox-side driver: git identity, setup, run `claude -p` |
| [`.github/workflows/`](.github/workflows/) | `ai-plan`, `ai-implement`, `ai-pr-failed`, and `ci` (`build` + `protected-paths`) |

## Setup (for your own copy)

You need a Docker account with Cloud Sandboxes enabled (pay-as-you-go) and either a Claude
subscription or an Anthropic API key.

1. **Use this template** to create your repo.
2. **Secrets** (Settings → Secrets and variables → Actions), set with `gh secret set NAME`:
   - `DOCKER_USER`, `DOCKER_PAT` — Docker username and personal access token.
   - `CLAUDE_CODE_OAUTH_TOKEN` — from `claude setup-token` (subscription), **or**
     `ANTHROPIC_API_KEY` — API key. If both are set, the OAuth token wins; to switch,
     delete one secret.
   - `AI_GITHUB_TOKEN` — fine-grained PAT, *only this repository*, permissions **Contents**,
     **Issues**, **Pull requests**: read & write. **Do not** grant Workflows or Administration.
3. **Labels:** `bash .ai/create-labels.sh owner/repo`.
4. **Repo settings:** allow auto-merge, automatically delete head branches, enable secret
   scanning and push protection (Settings → Code security).
5. **Ruleset** for the default branch (Settings → Rules → Rulesets → New branch ruleset):
   enforcement *Active*; target *default branch*; bypass list *Repository admin* in
   *pull requests only* mode; rules: *Restrict deletions*, *Block force pushes*,
   *Require a pull request before merging* (0 approvals), *Require status checks to pass*:
   `build` and `protected-paths`.
6. **CODEOWNERS:** replace `@bjhara` in `.github/CODEOWNERS` with your handle.

### Adapting to another stack

Edit three things:

- `.ai/setup.sh` — install your toolchain (e.g. `sudo apt-get install -y python3-venv` or Node.js).
- `.ai/config.env` — `VERIFY_CMD` (e.g. `pytest`, `npm test`) and add your package registry
  to `SBX_ALLOW_NETWORK` (e.g. `pypi.org,files.pythonhosted.org` or `registry.npmjs.org`).
  The cloud sandbox network is deny-all apart from that list, the Anthropic API and Debian apt.
- `.github/workflows/ci.yml` — the `build` job.

## Security model and accepted risks

This is an experiment on a public repo. Issue and comment text is untrusted input to an AI
agent that can write code and comments. What limits the damage:

- **No secrets in the repo.** Credentials live in Actions secrets and reach the sandbox
  only as environment variables. CI runs gitleaks; GitHub push protection is on.
- **Narrow token.** Claude's PAT covers only this repo and cannot change workflows or settings.
- **Sandboxed.** Claude runs in a throwaway cloud sandbox with a network allow-list and a TTL.
- **Checks gate merges.** PRs auto-merge only when `build` passes, and never when they touch
  `.ai/` or `.github/` (`protected-paths` fails them; the owner reviews and merges by hand).
- **Trust rule in the prompts.** Only comments from owners, members and collaborators count
  as answers; Claude's own comments carry a hidden marker.

Accepted risks:

- Claude acts as the **owner's account**. GitHub cannot tell its actions from the owner's,
  and anything the PAT allows Claude can technically do even if the prompts forbid it.
  `protected-paths` is a speed bump, not a lock.
- Collaborators with read or triage access also count as trusted commenters.
- Prompt injection through issue text can still produce a bad plan or a bad (but CI-passing) PR.

## Costs and timing

Each run creates a micro cloud sandbox for at most its TTL (45 min plan, 2 h implement) and
deletes it at the end. Measured in the [spike](docs/superpowers/spike-findings.md): sandbox
create ≈ 10 s, JDK + Maven install ≈ 50 s, `mvn verify` ≈ 13 s.

## Troubleshooting

- **Nothing happened after labelling:** check the Actions tab. The run exits early if you
  lack write access or `ai-working` is already set (remove it if a run died).
- **`CONNECT tunnel failed, response 403`:** a host is missing from `SBX_ALLOW_NETWORK`.
- **Leftover sandboxes:** `sbx --cloud ls` and `sbx --cloud rm --force <name>`; they also
  expire with their TTL.

## Docs

[Design](docs/superpowers/specs/2026-11-09-ai-issue-pipeline-design.md) ·
[Plan](docs/superpowers/plans/2026-11-09-ai-issue-pipeline.md) ·
[Spike findings](docs/superpowers/spike-findings.md)
