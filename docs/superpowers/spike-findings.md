# Spike findings (2026-11-09)

Throwaway workflow on branch `spike`, runs 42684993642 and 42685434865 (`ubuntu-24.04` runner, micro cloud sandbox).

| # | Question | Finding |
|---|---|---|
| 1 | Install + login in CI | `curl -fsSL https://get.docker.com \| sudo REPO_ONLY=1 sh && sudo apt-get install -y docker-sbx` works (no KVM needed for `--cloud`). `echo "$DOCKER_PAT" \| sbx login --username "$DOCKER_USER" --password-stdin` works (warns: no keychain, stored on disk — fine on an ephemeral runner). |
| 2 | Image | `sbx --cloud create ... claude` resolves the kit `docker.io/sbx/claude:latest`: Docker Hardened Images Debian 13, user `agent` (uid 1000, passwordless sudo), workdir `/home/agent/workspace`. Has `claude` (2.1.319), `git`, `gh`, `curl`, `apt-get`. **No Java/Maven.** Create takes ~10 s. |
| 3 | Headless Claude | `sbx --cloud exec -e CLAUDE_CODE_OAUTH_TOKEN <name> bash -lc 'claude -p "..." --dangerously-skip-permissions'` works with the subscription OAuth token; output streams to the Action log. Trivial prompt ~5 s. Claude can use `gh` with `GH_TOKEN`. |
| 4 | Env passing | Both `create -e KEY` and `exec -e KEY` reach the process. Bare `-e KEY` takes the value from the runner env (no value on the command line). |
| 5 | Network | **Cloud account default policy is `deny-all`**; the claude kit only opens Anthropic + Debian apt. GitHub and Maven Central were blocked (`CONNECT tunnel failed, response 403`). Fixed per sandbox with `--allow-network "github.com,api.github.com,*.githubusercontent.com,repo.maven.apache.org,repo1.maven.org"`. Account policy left untouched. A JVM proxy is pre-set via `JAVA_TOOL_OPTIONS`, so Maven works through it without config. |
| 6 | JDK 25 + Maven | Debian 13 apt has `openjdk-25-jdk-headless` (25.0.5) and `maven` (3.10.0): `sudo DEBIAN_FRONTEND=noninteractive apt-get install` takes ~45–50 s. First `mvn -B verify` on the demo app ~13 s. No prebuilt image needed for now. |
| 7 | PAT admin bypass | Deferred to Task 10 (needs the ruleset). |

## Design deviations

- New non-secret setting `SBX_ALLOW_NETWORK` in `.ai/config.env` (per-sandbox egress allow-list). Template users add their package registries here (e.g. `registry.npmjs.org`, `pypi.org,files.pythonhosted.org`).
- `SBX_AGENT=claude`; `setup.sh` only installs the toolchain (git/gh already present).
- Use `DEBIAN_FRONTEND=noninteractive` for apt.
