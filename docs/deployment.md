# Deployment

## Docker Compose

The supported workflow is Docker Compose with a dedicated container IP on an existing Docker network. The compose service and container are named `vvfs`.

```bash
docker compose up -d --build
```

Edit the sample values in [docker-compose.yml](../docker-compose.yml) before use:

- Set `VEEAM_SSH_PUBLIC_KEY` to a real public key, or set `VEEAM_PASSWORD`.
- Set the dedicated container IP.
- Set a unique static MAC address.
- Choose whether `VEEAM_PASSWORD` should remain empty.
- Set `PUID` and `PGID` to the desired source-data owner for the target host.
- Confirm `/opt/vvfs:/config`, or choose another host appdata path.
- Add any source bind mounts you want Veeam to browse. The default compose example mounts `/mnt` on the host to `/mnt` in the container.

The container runs systemd as PID 1. The compose file includes the runtime settings that were validated on a Docker host using cgroup v2:

```yaml
cgroup: host
tmpfs:
  - /run
  - /run/lock
volumes:
  - /sys/fs/cgroup:/sys/fs/cgroup:rw
```

This is intentionally narrower than `privileged: true`, but it still gives the container writable cgroup access and should be treated as a meaningful runtime permission.

`cgroup: host` makes the container use the host cgroup namespace. This gives systemd enough cgroup visibility to manage units inside the container, including Veeam services installed later by VBR. The `/sys/fs/cgroup` bind mount provides the matching cgroup filesystem view.

## Network

The compose file uses an external network named `vvfs_lan` by default:

```yaml
networks:
  vvfs_lan:
    name: vvfs_lan
    external: true
```

Create the macvlan network once on the Docker host:

```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=ens18 \
  vvfs_lan
```

Example local settings in `docker-compose.yml`:

```text
hostname: vvfs
ipv4_address: 192.168.1.31
mac_address: 02:42:c0:a8:01:1f
```

Use a unique locally administered unicast MAC address for each deployment. `02:xx:xx:xx:xx:xx` is a common private range; the example `02:42:c0:a8:01:1f` uses the container IP `192.168.1.31` encoded in the final four octets. Once the MAC is stable, name or reserve it in the router, switch, or Unraid network UI.

The compose file does not publish ports because the container has its own IP and listens directly on its container ports. The image does not declare `EXPOSE` ports for the same reason.

Docker macvlan commonly prevents the Docker host itself from reaching child container IPs. Test SSH from another LAN machine or from the VBR server unless a host-side macvlan interface is configured.

## Restores

Restore-created files may not retain the original source ownership or permissions, even when `PUID` and `PGID` match the expected host account. Check restored files after each restore and correct ownership or permissions on the Docker host or Unraid if required.

## Unraid

The project is intended to translate cleanly to Unraid later. A dedicated container IP through `br0` or custom networking is likely preferable there, because Veeam can then treat the sidecar more like a normal Linux machine without large host-port mappings.

Expected appdata mapping:

```text
/mnt/user/appdata/virtual-veeam-file-server:/config
```

For protected source data, mount `/mnt/user` or individual shares into the container according to the backup scope you want Veeam to see.

Do not mount user data over `/opt` inside the container. `/opt/veeam` is reserved for Veeam components deployed by VBR.

Do not publish an Unraid Community Applications XML template until Docker behavior and Veeam runtime requirements are proven.
