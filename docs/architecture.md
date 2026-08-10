# Architecture

Virtual Veeam File Server is a Linux userspace sidecar that Veeam Backup & Replication can manage over SSH.

```text
Veeam Backup & Replication
        |
        | SSH
        v
Container
        |
        | local filesystem access
        v
User-provided bind mounts
```

The image does not contain Veeam binaries. VBR is expected to deploy its current Linux transport components dynamically.

## Runtime Account

The managed SSH account is reconciled at startup from environment variables:

- `VEEAM_USERNAME`
- `VEEAM_PASSWORD`
- `VEEAM_SSH_PUBLIC_KEY`
- `PUID`
- `PGID`

The previously managed username is tracked in `/config/state/managed-user`. If the username changes, the old managed login account is removed without deleting `/config/veeam`.

The managed user receives passwordless sudo:

```text
<managed-user> ALL=(ALL) NOPASSWD: ALL
```

This allows VBR to deploy and manage Linux components over SSH.

The default managed user is `gdveeam` with UID/GID `1000:1000`.

## Persistent Paths

The only required appdata mapping is `/config`.

```text
/config/
├── state/
├── veeam/
├── veeam-os/
└── ssh/
    └── host-keys/
```

SSH host keys are generated once under `/config/ssh/host-keys` and reused on later starts.

`/opt/veeam` is a symlink to `/config/veeam`, allowing Veeam transport files to survive container recreation without requiring a second host bind mount.

VBR also deploys OS-level state outside `/opt/veeam`. The container persists this under `/config/veeam-os` and restores it before systemd starts:

```text
/config/veeam-os/
├── accounts/
├── dpkg/
├── etc-veeam/
├── systemd/
├── var-lib-veeamdata/
└── var-lib-veeam-usr-home/
```

The restored state includes Veeam service users/groups, `/etc/veeam`, selected dpkg metadata for Veeam-installed packages, Veeam systemd unit files/drop-ins, enabled unit names, `/var/lib/veeamdata`, and `/var/lib/veeam-usr-home`.

`virtual-veeam-state-sync.timer` periodically runs `veeam-state-sync.sh` so Veeam package installs or updates performed by VBR are copied back into `/config/veeam-os`.

## Systemd Runtime

VBR 13 installs Veeam Linux packages during managed-server setup. Those packages include systemd units such as:

```text
/opt/veeam/deployment/veeamdeploymentsvc --run-service
/opt/veeam/transport/veeamenvironment --run
/opt/veeam/transport/veeamtransport --run-service
```

The active image runs real systemd as PID 1. The entrypoint performs container-specific setup, restores persisted Veeam OS state, then executes `/sbin/init`. SSH runs as `virtual-veeam-sshd.service`; Veeam's deployed packages use their own packaged systemd units directly once installed or restored.

The deployment and environment daemons create Unix sockets Veeam expects:

```text
/run/veeam/veeamdeploymentCli
/run/veeamenvironment/socket
```

## Source Data

The image does not create or require a source path. Source bind mounts are configured by the user in Docker or Unraid.

The default Compose example maps `/mnt` on the host to `/mnt` in the container. Users can mount whatever data paths they want Veeam to browse, but `/opt` should not be used for source data because `/opt/veeam` is reserved for Veeam's deployed components.

Restore-created file ownership and permissions are controlled by Veeam's deployed Linux components. The container's `PUID` and `PGID` define the managed SSH account, but they do not guarantee restored files will inherit that account or preserve the original source metadata.
