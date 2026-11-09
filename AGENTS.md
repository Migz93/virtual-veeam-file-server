# Agent Guidelines

Read this before working in this repo.

## Project Facts

| | |
|---|---|
| App name | `virtual-veeam-file-server` |
| Image | `ghcr.io/migz93/virtual-veeam-file-server` |
| Host config directory | `/opt/vvfs` for local Compose testing |
| Container config directory | `/config` |
| Default network in Compose | external Docker network `vvfs_lan` with a dedicated container IP |
| Base image | `ubuntu:26.04` |
| Checks to run before closing out work | Devcontainer ShellCheck and management tests, plus host Docker container tests; see [TESTING.md](TESTING.md) |
| Veeam validation | Real VBR deployment is manual and must not be claimed as verified until tested. |

## Before Starting Work

Read `CLAUDE.md`, [docs/workflow.md](docs/workflow.md), [TESTING.md](TESTING.md)
and the checkout's ignored `LOCAL.md` when present. Private host paths, launcher
commands and resource/review records belong in `LOCAL.md`, never tracked docs.

Check branch/dirty state and concurrent chat ownership before editing. Fetch and
fast-forward the intended base, then create or continue a task branch. Preserve
uncommitted work; never force/reset or overwrite another chat's changes.

- Work on short-lived `feat/*`, `fix/*`, `docs/*`, `ci/*` or `chore/*` branches.
- PRs target `develop`; `main` is stable.
- Never commit directly to `develop` or `main` without an explicit request.

## Development Environment

Use the on-demand `.devcontainer` as `vscode` for source edits, dependency setup,
ShellCheck and Python management tests. Keep project dependencies off the host
and clients. Initial container scaffolding/lifecycle management runs on the host;
the launcher uses Python's standard library and the official Dev Container CLI.
Read `LOCAL.md` for the maintained checkout and launcher, or use the portable
commands in [docs/workflow.md](docs/workflow.md).

Run authenticated Git, Claude/CodeRabbit reviews, runtime Docker image builds and
`tests/run-container-tests.sh` on the host. The tool container binds only this
source checkout; it does not separately mount the Docker socket, host authentication
directories, live config, source data or persistent volumes, and publishes no ports.
The source bind includes readable ignored files: Git ignore rules do not filter
bind mounts. Keep passwords, tokens, SSH keys and other credentials outside the
checkout. Runtime systemd tests are separate disposable containers; see `TESTING.md`.

Record exact task resources in ignored `LOCAL.md`. After validation and review,
check concurrent chat ownership and active processes, then remove the development
container with the launcher. Preserve build cache, private review records,
unexpected resources and other chats' work. A task or merge does not authorize
persistent deployment, real VBR use, LAN networking or source-data mounts.

## Docker Expectations

This project should be validated against real containers whenever Docker is available.

Use the app name directly for local image and container names:

```bash
docker build -t virtual-veeam-file-server:test .
```

For persistent local testing, ask the user before choosing host paths, SSH public keys, network names, or a dedicated IP. The usual local config path is expected to be:

```text
/opt/vvfs:/config
```

Do not create or assume source-data paths in the image. Source bind mounts are user-controlled.

## Implementation Principles

- Do not bake Veeam binaries into the image.
- Do not bake passwords or private keys into the image.
- Keep authentication driven by environment variables.
- Preserve `/config/ssh/host-keys` across container recreation.
- Keep `/opt/veeam` persistent through `/config/veeam`.
- Preserve files under `/config/veeam` when reconciling username changes.
- Do not require Docker `--privileged` unless testing proves it unavoidable.
- Do not claim untested Veeam behavior as confirmed.

## Documentation

Update docs as part of behavior changes:

- Docker/runtime changes: [docs/deployment.md](docs/deployment.md)
- Architecture or persistence changes: [docs/architecture.md](docs/architecture.md)
- Workflow/release changes: [docs/workflow.md](docs/workflow.md)
- Test behavior: [TESTING.md](TESTING.md)

Keep docs factual and concise.

## Review Gate

`claude-review` is a maintainer-managed helper, not a script shipped in this
repository. On another host, ask the maintainer for the approved helper and setup,
or arrange the review on an existing maintainer review host. On a configured host,
run `claude-review --base origin/develop --tests 'Describe the checks that passed'`
from the clean, committed checkout. The command prints its saved run directory;
use that exact directory for `--previous` in the delta/full loop below.
If the helper is unavailable, provide the completed checks and request maintainer
review; do not claim cross-AI clearance or bypass the review gate. Keep only
non-secret installation paths and run records in ignored `LOCAL.md`; credentials
must stay outside the checkout.

After required checks pass, commit completed work using Conventional Commits on
the task branch. Run automatic local Claude cross-AI review from the host with
explicit base `origin/develop`. Reviewers must not recursively launch reviews.
Follow the shared review runner's saved-run delta/full loop: assess findings,
fix valid issues, rerun affected checks, commit, obtain a clean delta, then a clean
fresh full review of the current base/head. Rewritten history or a moved base
requires a new full review. Record exact revisions and saved runs in `LOCAL.md`.

CodeRabbit CLI review, pushing, PR creation, merging and release remain owner
decisions; ask before those actions unless already requested. Use semantic PR titles, such as `chore: add disposable
development tooling`. Tooling changes do not trigger live deployment.
