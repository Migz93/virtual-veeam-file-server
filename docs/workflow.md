# Workflow

This project follows Miguel's Hubarr-style workflow where relevant.

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

Dependabot checks Docker and GitHub Actions weekly and assigns new update PRs to `Migz93`. Existing schedules, limits and commit-message rules remain unchanged.

Both entries target `develop`, which is currently the repository's default branch. Their `assignees` lists therefore apply to version and security update PRs. GitHub ignores these assignees for security updates when an entry targets a non-default branch; if the default branch or update targets change, retain the version-update entries and configure assignees for the default branch too. See the [GitHub assignees reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference#assignees).

## Review Gate

When implementation is complete and the user is happy with local validation, stop before opening a PR and ask whether they want:

1. Cross-AI review
2. CodeRabbit CLI review
3. Push and open the PR
