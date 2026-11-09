# Workflow

This project follows Miguel's Hubarr-style workflow where relevant.

## Development Tools

The project is Bash and Docker; there is no npm/Python application dependency
manifest. Runtime packages remain in the root `Dockerfile`. The separate
`.devcontainer/Dockerfile` provides Bash, ShellCheck, Git and Python for isolated
editing, linting and lifecycle tests on the same Ubuntu release as the runtime.
Python management code uses only the standard library.

Use Docker and the official Dev Container CLI on the development host. The
maintained host's ignored `LOCAL.md` records its short launcher commands. From
another checkout, the equivalent portable commands are:

```bash
python3 .devcontainer/manage.py up
python3 .devcontainer/manage.py exec bash -c 'shellcheck scripts/*.sh tests/*.sh'
python3 .devcontainer/manage.py exec python3 -m unittest discover -s tests -p 'test_*.py'
python3 .devcontainer/manage.py status
python3 .devcontainer/manage.py down
```

`exec` accepts a command and separate arguments; use `bash -c` explicitly for
wildcards or shell operators. Use the running container as `vscode` to edit
source and install development tools. Do not install project dependencies on
the host. Host Git and review authentication stay outside the tool container.

Launcher commands are intentionally serialized for each host user. An `exec`
command holds the lifecycle lock until it exits; other launcher commands,
including another `exec` or `status`, return a try-later message meanwhile.
Finish or close that command before using the launcher again. This also prevents
cleanup during a command whose process name happens to match an allowed idle name.

The tool container has one source bind and no separate Docker socket or host
authentication-directory mounts, published ports or persistent volumes. The source
bind includes readable ignored files; Git ignore rules do not exclude them from
the container. Keep passwords, tokens, SSH keys and other credentials outside the
checkout. Image-installed tools survive rebuilding; writable home,
caches and ad-hoc installed dependencies disappear when it is removed. Add
required tools to its Dockerfile. The manager rejects mismatched ownership/mounts
and defers cleanup when it detects active development processes. The process-name
check is best-effort and can miss processes that use an allowed idle name. Use the
launcher's `exec` command and check concurrent chats before cleanup.
One fixed development container name is supported per Docker host;
preserve another checkout's container rather than replacing it.

Runtime builds and the disposable integration suite run with Docker on the
host, as described in [TESTING.md](../TESTING.md). They do not require real VBR
credentials, a LAN IP or a persistent Compose deployment. Do not run the example
Compose deployment as a development startup command.

## Branches

- `develop` receives normal work through PRs.
- `main` is stable/released.
- Work branches use names like `feat/initial-docker-prototype`, `fix/auth-reconciliation`, `docs/readme-update`, or `ci/docker-tests`.

Do not push directly to `develop` or `main` unless the user explicitly asks.

## Pull Requests

Work-branch PRs target `develop`. Use semantic PR titles because they become release-note entries.

Suggested PR body:

```markdown
## Summary

One or two sentences on what changed and why.

## Changes

- Meaningful change
- Another meaningful change

## Test plan

- Commands run
- Anything not verified locally
```

## Image Publishing

Pushes to `develop` should publish:

```text
ghcr.io/migz93/virtual-veeam-file-server:develop
ghcr.io/migz93/virtual-veeam-file-server:sha-<shortsha>
```

Pushes to `main` should publish:

```text
ghcr.io/migz93/virtual-veeam-file-server:latest
ghcr.io/migz93/virtual-veeam-file-server:sha-<shortsha>
```

The SHA tag format intentionally matches Hubarr's `sha-<shortsha>` convention.

Base image and dependency update PRs should receive normal review and CI. Do not auto-merge them initially, because Veeam compatibility depends on Linux, systemd, and OpenSSH behavior.

## Dependency Updates

Dependabot checks both the runtime and development Dockerfiles, plus GitHub Actions, weekly and assigns new update PRs to `Migz93`. Existing schedules, limits and commit-message rules remain unchanged.

Both entries target `develop`, which is currently the repository's default branch. Their `assignees` lists therefore apply to version and security update PRs. GitHub ignores these assignees for security updates when an entry targets a non-default branch; if the default branch or update targets change, retain the version-update entries and configure assignees for the default branch too. See the [GitHub assignees reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference#assignees).

## Review Gate

The `claude-review` helper is maintained separately from this repository. See
[AGENTS.md](../AGENTS.md#review-gate) for the command, how to arrange setup or review
on another host, and the fallback when it is unavailable. Do not claim clearance
without a completed review.

After the required checks pass, commit work on the task branch and run the
standing automatic local Claude cross-AI review against `origin/develop`. Resolve
valid findings and complete the saved-run delta/full loop until a fresh full
review clears the current base/head; keep private records in ignored `LOCAL.md`.
Reviewers do not recursively launch reviews.

CodeRabbit CLI review, pushing, PR creation, merging and release require the
owner's request. Use semantic PR titles. Tooling/documentation work does not trigger a
live deployment; persistent runtime setup and real VBR testing are separate
operations.

## PR Title Validation

The Semantic PR check runs on `pull_request` events (opened, edited,
synchronize and reopened). It validates the title from the event payload without
checking out PR code, accessing secrets or requesting token permissions. Accepted
types are `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`,
`revert`, `style` and `test`; optional scopes and a breaking-change `!` are
supported. Keep the title accurate when reviewing and merging a PR.

The check runs the workflow from the PR merge ref, so a PR can change its own
formatting check. Review workflow edits and the final title before merging;
this check is a formatting aid, not a trusted approval boundary. Fork PRs may
wait for GitHub's normal contributor approval before checks run.
