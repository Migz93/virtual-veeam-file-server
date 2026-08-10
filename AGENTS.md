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
| Checks to run before closing out work | `shellcheck scripts/*.sh tests/*.sh`, `docker build -t virtual-veeam-file-server:test .`, `IMAGE_NAME=virtual-veeam-file-server:test tests/run-container-tests.sh` |
| Veeam validation | Real VBR deployment is manual and must not be claimed as verified until tested. |

## Before Starting Work

If this directory has become a git repository, check the current branch before editing:

```bash
git branch --show-current
```

Use Hubarr's branch model:

- Work happens on short-lived `feat/*`, `fix/*`, `docs/*`, `ci/*`, or `chore/*` branches.
- PRs target `develop`.
- `main` is the stable branch.
- Do not commit directly to `develop` or `main` unless the user explicitly requests it.

This workspace may be bootstrapped before git exists. In that case, proceed in-place and mention that branch checks were not available.

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

When implementation work is complete and the user is happy with the local result, stop before opening a PR and ask whether they want:

1. Cross-AI review
2. CodeRabbit CLI review
3. Push and open the PR

Follow Hubarr's convention that PR titles are semantic, for example `feat: add initial docker prototype`.
