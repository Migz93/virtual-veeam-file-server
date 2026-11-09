<!-- shared: structure — headings kept in sync across Migz93 self-hosted apps, content is app-specific -->

# Testing

Validation covers development tooling, runtime behavior and manual Veeam integration. Development-container checks lint scripts and test lifecycle safety. Host Docker container tests check the image, entrypoint, SSH, persistence, and healthcheck behavior. Manual Veeam validation checks the parts that require a real Veeam Backup & Replication server.

## Commands

| Command | What it does |
|---|---|
| In the devcontainer: `shellcheck scripts/*.sh tests/*.sh` | Lints shell scripts |
| In the devcontainer: `python3 -m unittest discover -s tests -p 'test_*.py'` | Tests lifecycle ownership, cleanup, command forwarding and build failure without Docker access |
| On the host: `docker build -t virtual-veeam-file-server:test .` | Optional standalone runtime build |
| On the host: `IMAGE_NAME=virtual-veeam-file-server:test tests/run-container-tests.sh` | Builds that image and runs the complete container suite |

Use a unique task image tag instead of the shared example tag for concurrent
local work. See [development commands](docs/workflow.md#development-tools) and
ignored `LOCAL.md` for the maintained host launcher. CI runs both **Validate
Container** (ShellCheck, runtime build, integration suite) and **Validate
Development Tools** (development image, ShellCheck, lifecycle tests). The separate
semantic PR-title check is also expected. Publishing builds AMD64 and ARM64;
the runtime suite runs only on the executing host's architecture.

## Disposable Runtime Resources

Run the suite on the Docker host, outside the tool container. It requires Bash,
Docker and the OpenSSH client tools (`ssh`, `ssh-keygen`). Each run logs its ID
and temporary directory, labels its test containers, and names them
`zdev-virtual-veeam-file-server-e2e-<run>-<case>`. It generates disposable SSH keys,
binds only temporary config directories, and publishes SSH only on loopback at
an allocated port. It does not use the example Compose network or live data.

The suite uses real systemd as PID 1, host cgroup namespace and a writable
`/sys/fs/cgroup` bind, plus tmpfs `/run` and `/run/lock`, matching runtime needs.
The development tool container needs none of these permissions. Tests check
startup health, SSH and synthetic persisted OS state; they do not install real
Veeam transport packages or validate a backup/restore.

The exit trap removes that run's containers and temporary config/keys, using
the tested image for permission cleanup. If interrupted cleanup fails, inspect
the logged run ID, labels and exact paths before removing only those resources.
Retain image/build cache; do not prune unrelated resources. Never use a real
`/config`, source-data mount, VBR credentials or persistent host directory here.

## Container Tests

The test suite in [tests/run-container-tests.sh](tests/run-container-tests.sh) verifies:

| Test | What it checks |
|---|---|
| Missing credentials | Startup fails if neither `VEEAM_PASSWORD` nor `VEEAM_SSH_PUBLIC_KEY` is supplied |
| Public-key auth | SSH login works with a generated key |
| `/opt/veeam` persistence | `/opt/veeam` resolves to `/config/veeam` |
| SSH host-key persistence | Reusing `/config` keeps the same SSH server fingerprint |
| Username reconciliation | Changing `VEEAM_USERNAME` removes the previous managed login account |
| Veeam OS-state restore | Persisted users, dpkg metadata, and systemd units can be restored from `/config/veeam-os` |
| UID/GID claim | The default `1000:1000` managed account can claim Ubuntu's base UID/GID |
| Password-only mode | Password auth is enabled and stale `authorized_keys` is removed |
| systemd runtime | systemd runs as PID 1 and SSH runs through `virtual-veeam-sshd.service` |

## Manual Veeam Validation

Do not mark Veeam behavior as confirmed until tested with a real VBR server.

The currently validated path includes SSH connection, privilege elevation, transport deployment, file browsing, backup, restore, and container recreation with persisted Veeam components.

When restore testing, record whether the restore succeeds and then check ownership and permissions from the Docker host or Unraid. Restored files may need manual ownership or permission correction after restore.

## Manual Smoke Test

For local Docker verification with Compose:

```bash
# Edit docker-compose.yml with a real SSH public key, dedicated IP, MAC address, and paths.
docker compose up -d --build
docker logs vvfs 2>&1 | tail -20
docker inspect -f '{{.State.Health.Status}}' vvfs
```

Then test SSH from a machine that can reach the container IP:

```bash
ssh gdveeam@192.168.1.31
```
