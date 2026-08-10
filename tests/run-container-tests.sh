#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="${IMAGE_NAME:-virtual-veeam-file-server:test}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
CONTAINERS=()
RUN_DETACHED_NAME=
SYSTEMD_DOCKER_ARGS=(
  --cgroupns=host
  --tmpfs /run
  --tmpfs /run/lock
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw
)

cleanup() {
  for container in "${CONTAINERS[@]:-}"; do
    docker rm -f "${container}" >/dev/null 2>&1 || true
  done
  if [[ -d "${WORK_DIR}" ]]; then
    docker run --rm -v "${WORK_DIR}:/work" ubuntu:26.04 bash -c 'chmod -R u+rwX,go+rwX /work 2>/dev/null || true' >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

log() {
  printf '[test] %s\n' "$*"
}

container_name() {
  printf 'vvfs-test-%s-%s' "$1" "$RANDOM"
}

wait_healthy() {
  local container="$1"
  local status

  for _ in {1..40}; do
    status="$(docker inspect -f '{{.State.Health.Status}}' "${container}")"
    if [[ "${status}" == "healthy" ]]; then
      return 0
    fi
    if [[ "${status}" == "unhealthy" ]]; then
      docker logs "${container}" >&2 || true
      return 1
    fi
    sleep 1
  done

  docker logs "${container}" >&2 || true
  echo "container ${container} did not become healthy" >&2
  return 1
}

run_detached() {
  local label="$1"
  shift
  local name
  name="$(container_name "${label}")"
  CONTAINERS+=("${name}")
  docker run -d --name "${name}" --network bridge "${SYSTEMD_DOCKER_ARGS[@]}" "$@" "${IMAGE_NAME}" >/dev/null
  RUN_DETACHED_NAME="${name}"
}

get_ssh_port() {
  docker port "$1" 22/tcp | sed 's/.*://'
}

log "Building ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${ROOT_DIR}"

log "Testing startup fails without credentials"
if docker run --rm --network bridge "${SYSTEMD_DOCKER_ARGS[@]}" "${IMAGE_NAME}" >/tmp/vvfs-no-creds.out 2>&1; then
  cat /tmp/vvfs-no-creds.out >&2
  echo "container unexpectedly started without credentials" >&2
  exit 1
fi
grep -q "Set VEEAM_PASSWORD, VEEAM_SSH_PUBLIC_KEY, or both" /tmp/vvfs-no-creds.out

log "Generating test SSH key"
ssh-keygen -q -t ed25519 -N '' -f "${WORK_DIR}/id_ed25519"
PUBLIC_KEY="$(cat "${WORK_DIR}/id_ed25519.pub")"

log "Testing public-key-only SSH and persistent /opt/veeam"
CONFIG_ONE="${WORK_DIR}/config-one"
mkdir -p "${CONFIG_ONE}"
run_detached key-only -p 127.0.0.1::22 -v "${CONFIG_ONE}:/config" -e VEEAM_SSH_PUBLIC_KEY="${PUBLIC_KEY}"
container="${RUN_DETACHED_NAME}"
wait_healthy "${container}"
ssh_port="$(get_ssh_port "${container}")"
ssh -i "${WORK_DIR}/id_ed25519" -p "${ssh_port}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null gdveeam@127.0.0.1 true
docker exec "${container}" test -L /opt/veeam
docker exec "${container}" test "$(docker exec "${container}" readlink /opt/veeam)" = "/config/veeam"
docker exec "${container}" test "$(docker exec "${container}" cat /proc/1/comm)" = "systemd"
docker exec "${container}" systemctl is-active --quiet virtual-veeam-sshd.service
fingerprint_one="$(ssh-keygen -lf "${CONFIG_ONE}/ssh/host-keys/ssh_host_ed25519_key.pub" | awk '{print $2}')"
docker rm -f "${container}" >/dev/null

run_detached key-again -p 127.0.0.1::22 -v "${CONFIG_ONE}:/config" -e VEEAM_SSH_PUBLIC_KEY="${PUBLIC_KEY}"
container="${RUN_DETACHED_NAME}"
wait_healthy "${container}"
fingerprint_two="$(ssh-keygen -lf "${CONFIG_ONE}/ssh/host-keys/ssh_host_ed25519_key.pub" | awk '{print $2}')"
[[ "${fingerprint_one}" == "${fingerprint_two}" ]]

log "Testing username reconciliation preserves /config/veeam"
docker run --rm -v "${CONFIG_ONE}:/config" ubuntu:26.04 touch /config/veeam/preserved-marker
docker rm -f "${container}" >/dev/null
run_detached rename -v "${CONFIG_ONE}:/config" -e VEEAM_USERNAME=newveeam -e VEEAM_SSH_PUBLIC_KEY="${PUBLIC_KEY}"
container="${RUN_DETACHED_NAME}"
wait_healthy "${container}"
docker exec "${container}" id newveeam >/dev/null
if docker exec "${container}" id gdveeam >/dev/null 2>&1; then
  echo "old managed user still exists after username change" >&2
  exit 1
fi
docker exec "${container}" test -f /config/veeam/preserved-marker

log "Testing Veeam OS-state restore"
CONFIG_RESTORE="${WORK_DIR}/config-restore"
mkdir -p \
  "${CONFIG_RESTORE}/veeam-os/accounts" \
  "${CONFIG_RESTORE}/veeam-os/dpkg/info" \
  "${CONFIG_RESTORE}/veeam-os/dpkg/status.d" \
  "${CONFIG_RESTORE}/veeam-os/systemd/units"
cat >"${CONFIG_RESTORE}/veeam-os/accounts/group" <<'EOF'
veeam-grp-test:x:550:veeam-usr-test
veeam-usr-test:x:450:
EOF
cat >"${CONFIG_RESTORE}/veeam-os/accounts/passwd" <<'EOF'
veeam-usr-test:x:450:450::/var/lib/veeam-usr-home/veeam-usr-test:/usr/sbin/nologin
EOF
cat >"${CONFIG_RESTORE}/veeam-os/dpkg/status.d/veeamfake.status" <<'EOF'
Package: veeamfake
Status: install ok installed
Priority: optional
Section: admin
Maintainer: Test
Architecture: amd64
Version: 1.0
Description: Fake Veeam package for restore tests
EOF
cat >"${CONFIG_RESTORE}/veeam-os/dpkg/info/veeamfake.list" <<'EOF'
/.
/opt
/opt/veeam
EOF
cat >"${CONFIG_RESTORE}/veeam-os/systemd/units/veeamfake.service" <<'EOF'
[Unit]
Description=Fake Veeam restore test unit

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
printf '%s\n' veeamfake.service >"${CONFIG_RESTORE}/veeam-os/systemd/enabled-units"
run_detached restore -v "${CONFIG_RESTORE}:/config" -e VEEAM_SSH_PUBLIC_KEY="${PUBLIC_KEY}"
container="${RUN_DETACHED_NAME}"
wait_healthy "${container}"
docker exec "${container}" id veeam-usr-test >/dev/null
docker exec "${container}" getent group veeam-grp-test >/dev/null
docker exec "${container}" dpkg-query -W veeamfake >/dev/null
docker exec "${container}" systemctl is-enabled --quiet veeamfake.service

log "Testing managed user can claim the base Ubuntu UID"
CONFIG_THREE="${WORK_DIR}/config-three"
mkdir -p "${CONFIG_THREE}"
run_detached uid-1000 -v "${CONFIG_THREE}:/config" -e VEEAM_SSH_PUBLIC_KEY="${PUBLIC_KEY}"
container="${RUN_DETACHED_NAME}"
wait_healthy "${container}"
docker exec "${container}" id gdveeam >/dev/null
docker exec "${container}" test "$(docker exec "${container}" id -u gdveeam)" = "1000"
docker exec "${container}" test "$(docker exec "${container}" id -g gdveeam)" = "1000"
docker exec "${container}" test "$(docker exec "${container}" id -gn gdveeam)" = "gdveeam"
if docker exec "${container}" id ubuntu >/dev/null 2>&1; then
  echo "default ubuntu account still exists after UID claim" >&2
  exit 1
fi

log "Testing password-only mode enables password auth and removes authorized_keys"
CONFIG_TWO="${WORK_DIR}/config-two"
mkdir -p "${CONFIG_TWO}"
run_detached password-only -v "${CONFIG_TWO}:/config" -e VEEAM_PASSWORD=secret-test-password
container="${RUN_DETACHED_NAME}"
wait_healthy "${container}"
docker exec "${container}" grep -q '^PasswordAuthentication yes$' /run/virtual-veeam-file-server/sshd_config
docker exec "${container}" test ! -e /home/gdveeam/.ssh/authorized_keys

log "All container tests passed"
