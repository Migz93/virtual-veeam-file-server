# Virtual Veeam File Server

[![GitHub Activity][commits-shield]][commits]
[![License][license-shield]][license]
[![Project Maintainer][maintainer-shield]][user_profile]
[![Buy me a coffee][buymecoffeebadge]][buymecoffee]

Virtual Veeam File Server is an unofficial Docker container that gives Veeam Backup & Replication file-level access to paths mounted from your Docker host.

Run the container, mount the folders you want to protect, then add the container to Veeam as a Linux file server. It is mainly intended for backing up Unraid without using SMB, but it can run on any Docker host that can give the container a dedicated reachable IP.

## What It Does

- Gives Veeam a Linux server it can connect to over SSH
- Lets you mount host paths into the container for Veeam to browse
- Keeps the container identity stable when it is recreated
- Keeps Veeam's installed components under `/config`
- Uses a dedicated container IP instead of port mappings

## How It Works

Veeam connects to the container over SSH and installs the components it needs, the same way it would with a normal Linux server. Your storage is made available through Docker path mappings, such as `/mnt:/mnt`, and you choose the folders to back up from inside Veeam.

Do not mount source data over `/opt`. The container uses `/opt/veeam` for Veeam's deployed components.

## Quick Start

### Requirements

- Docker or Docker Compose
- A dedicated reachable IP for the container
- Veeam Backup & Replication 13.1 or newer for Ubuntu 26.04 support
- An SSH public key or password for VBR to use
- A persistent `/config` directory
- One or more data mounts for the files you want Veeam to browse

### Docker

```bash
docker run -d \
  --name vvfs \
  --hostname vvfs \
  --network vvfs_lan \
  --ip 192.168.1.31 \
  --mac-address 02:42:c0:a8:01:1f \
  --cgroupns=host \
  --tmpfs /run \
  --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v /opt/vvfs:/config \
  -v /mnt:/mnt \
  -e VEEAM_USERNAME=gdveeam \
  -e VEEAM_SSH_PUBLIC_KEY="ssh-ed25519 AAAA... example@host" \
  -e PUID=1000 \
  -e PGID=1000 \
  --restart unless-stopped \
  ghcr.io/migz93/virtual-veeam-file-server:latest
```

### Docker Compose

```yaml
services:
  vvfs:
    image: ghcr.io/migz93/virtual-veeam-file-server:latest
    container_name: vvfs
    hostname: vvfs
    cgroup: host
    restart: unless-stopped
    networks:
      vvfs_lan:
        ipv4_address: 192.168.1.31
        mac_address: 02:42:c0:a8:01:1f
    environment:
      VEEAM_USERNAME: gdveeam
      VEEAM_PASSWORD: ""
      VEEAM_SSH_PUBLIC_KEY: "ssh-ed25519 AAAA... example@host"
      PUID: 1000
      PGID: 1000
    volumes:
      - /opt/vvfs:/config
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
      - /mnt:/mnt
    tmpfs:
      - /run
      - /run/lock

networks:
  vvfs_lan:
    external: true
```

Edit the sample values in [docker-compose.yml](docker-compose.yml), especially the SSH key, IP address, MAC address, and path mappings, then start it:

```bash
docker compose up -d
```

### Configuration

| Variable | Default | Notes |
|---|---:|---|
| `VEEAM_USERNAME` | `gdveeam` | Managed SSH login account. |
| `VEEAM_PASSWORD` | empty | Optional password. Never logged. |
| `VEEAM_SSH_PUBLIC_KEY` | empty | Public SSH key for Veeam. Recommended auth method. |
| `PUID` | `1000` | UID for the managed account. |
| `PGID` | `1000` | GID for the managed account. |

### Path Mappings

| Host path | Container path | Purpose |
|---|---|---|
| `/opt/vvfs` | `/config` | Persistent appdata for SSH identity and Veeam-installed components. |
| `/mnt` | `/mnt` | Example data mount. Veeam browses this path and you choose what to protect. |

### First Setup

1. Create or choose a Docker network that gives the container a dedicated LAN IP.
2. Start the container with SSH credentials and your data mount.
3. Add the container to VBR as a Linux managed server using the configured username.
4. Browse the mounted path from Veeam, for example `/mnt`.
5. Select the folders you want to protect from inside Veeam.

## Important Limitations

### Restore Ownership

Restored files may not retain the original source ownership or permissions. After a restore, check the restored files from the Docker host and adjust ownership or permissions if needed.

### Runtime Permissions

The container runs real systemd as PID 1. It does not require `privileged: true`, but it does require host cgroup access through `cgroup: host` and `/sys/fs/cgroup:/sys/fs/cgroup:rw`.

### Ubuntu Compatibility

The image is based on Ubuntu 26.04. Use Veeam Backup & Replication 13.1 or newer, or another VBR version that supports deploying to Ubuntu 26.04 Linux systems.

## Documentation

- [Deployment](docs/deployment.md)
- [Architecture](docs/architecture.md)
- [Testing](TESTING.md)
- [Security](SECURITY.md)
- [Workflow](docs/workflow.md)

## AI Transparency

Virtual Veeam File Server was created with heavy AI assistance.

Codex was used throughout the project for implementation help, debugging, refactoring, documentation, review, and iteration. The intent is not to hide that. The project combines hands-on testing and direction with AI-assisted development work.

## Credits And Inspiration

Virtual Veeam File Server started from wanting to back up Unraid with Veeam as a file server rather than through SMB.

It was also inspired by [pk1057/veeam](https://github.com/pk1057/veeam), an earlier Docker-based Veeam container project aimed at backing up Unraid.

[buymecoffee]: https://www.buymeacoffee.com/Migz93
[buymecoffeebadge]: https://img.shields.io/badge/buy%20me%20a%20coffee-donate-yellow.svg?style=for-the-badge
[commits-shield]: https://img.shields.io/github/commit-activity/y/Migz93/virtual-veeam-file-server.svg?style=for-the-badge
[commits]: https://github.com/Migz93/virtual-veeam-file-server/commits/main
[license]: https://github.com/Migz93/virtual-veeam-file-server/blob/main/LICENSE
[license-shield]: https://img.shields.io/github/license/Migz93/virtual-veeam-file-server.svg?style=for-the-badge
[maintainer-shield]: https://img.shields.io/badge/maintainer-Migz93-blue.svg?style=for-the-badge
[user_profile]: https://github.com/Migz93
