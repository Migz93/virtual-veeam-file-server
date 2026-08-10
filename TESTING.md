<!-- shared: structure — headings kept in sync across Migz93 self-hosted apps, content is app-specific -->

# Testing

Virtual Veeam File Server has two validation layers. Local container tests check the image, entrypoint, SSH, persistence, and healthcheck behavior. Manual Veeam validation checks the parts that require a real Veeam Backup & Replication server.

## Commands

| Command | What it does |
|---|---|
| `shellcheck scripts/*.sh tests/*.sh` | Lints shell scripts |
| `docker build -t virtual-veeam-file-server:test .` | Builds the local test image |
| `IMAGE_NAME=virtual-veeam-file-server:test tests/run-container-tests.sh` | Builds and runs the container test suite |

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
