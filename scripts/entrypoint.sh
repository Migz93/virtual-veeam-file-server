#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR=/config
STATE_DIR="${CONFIG_DIR}/state"
MANAGED_USER_FILE="${STATE_DIR}/managed-user"
HOST_KEY_DIR="${CONFIG_DIR}/ssh/host-keys"
VEEAM_DIR="${CONFIG_DIR}/veeam"
VEEAM_OS_STATE_DIR="${CONFIG_DIR}/veeam-os"
RUNTIME_DIR=/run/virtual-veeam-file-server
SSHD_CONFIG="${RUNTIME_DIR}/sshd_config"
SUDOERS_FILE=/etc/sudoers.d/virtual-veeam-file-server

log() {
  printf '[virtual-veeam-file-server] %s\n' "$*"
}

fail() {
  printf '[virtual-veeam-file-server] ERROR: %s\n' "$*" >&2
  exit 1
}

is_int() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

validate_env() {
  [[ -n "${VEEAM_PASSWORD:-}" || -n "${VEEAM_SSH_PUBLIC_KEY:-}" ]] || fail "Set VEEAM_PASSWORD, VEEAM_SSH_PUBLIC_KEY, or both."
  [[ "${VEEAM_USERNAME:-}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "VEEAM_USERNAME must be a valid Linux account name."
  is_int "${PUID:-}" || fail "PUID must be numeric."
  is_int "${PGID:-}" || fail "PGID must be numeric."

  if [[ -n "${VEEAM_SSH_PUBLIC_KEY:-}" ]]; then
    ssh-keygen -l -f <(printf '%s\n' "${VEEAM_SSH_PUBLIC_KEY}") >/dev/null 2>&1 \
      || fail "VEEAM_SSH_PUBLIC_KEY is not a valid public SSH key."
  fi
}

prepare_directories() {
  mkdir -p "${STATE_DIR}" "${HOST_KEY_DIR}" "${VEEAM_DIR}" "${VEEAM_OS_STATE_DIR}" "${RUNTIME_DIR}" /opt /run/sshd
  chmod 0755 "${CONFIG_DIR}" "${CONFIG_DIR}/ssh" "${HOST_KEY_DIR}" "${VEEAM_DIR}" "${VEEAM_OS_STATE_DIR}" "${RUNTIME_DIR}" /run/sshd

  if [[ -e /opt/veeam && ! -L /opt/veeam ]]; then
    if [[ -d /opt/veeam && -z "$(find /opt/veeam -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      rmdir /opt/veeam
    else
      fail "/opt/veeam exists and is not an empty directory or symlink; cannot replace it with persistent /config/veeam link."
    fi
  fi

  ln -sfn "${VEEAM_DIR}" /opt/veeam
}

restore_veeam_groups() {
  local group_file="${VEEAM_OS_STATE_DIR}/accounts/group"
  local name gid members member

  [[ -f "${group_file}" ]] || return 0

  while IFS=: read -r name _ gid members; do
    [[ -n "${name}" && -n "${gid}" ]] || continue

    if ! getent group "${name}" >/dev/null 2>&1 && ! getent group "${gid}" >/dev/null 2>&1; then
      groupadd --gid "${gid}" "${name}"
    fi
  done <"${group_file}"

  while IFS=: read -r name _ gid members; do
    [[ -n "${name}" && -n "${members}" ]] || continue

    IFS=, read -ra member_list <<<"${members}"
    for member in "${member_list[@]}"; do
      if id "${member}" >/dev/null 2>&1 && getent group "${name}" >/dev/null 2>&1; then
        usermod -a -G "${name}" "${member}"
      fi
    done
  done <"${group_file}"
}

restore_veeam_users() {
  local passwd_file="${VEEAM_OS_STATE_DIR}/accounts/passwd"
  local name uid gid home shell

  [[ -f "${passwd_file}" ]] || return 0

  while IFS=: read -r name _ uid gid _ home shell; do
    [[ -n "${name}" && -n "${uid}" && -n "${gid}" ]] || continue

    if ! id "${name}" >/dev/null 2>&1 && ! getent passwd "${uid}" >/dev/null 2>&1; then
      useradd \
        --uid "${uid}" \
        --gid "${gid}" \
        --home-dir "${home}" \
        --shell "${shell:-/usr/sbin/nologin}" \
        --no-create-home \
        "${name}"
    fi
  done <"${passwd_file}"
}

restore_veeam_accounts() {
  restore_veeam_groups
  restore_veeam_users
  restore_veeam_groups
}

ensure_persistent_link() {
  local target="${1}"
  local persistent_dir="${2}"

  mkdir -p "${persistent_dir}" "$(dirname "${target}")"

  if [[ -L "${target}" ]]; then
    ln -sfn "${persistent_dir}" "${target}"
    return 0
  fi

  if [[ -e "${target}" ]]; then
    cp -a "${target}/." "${persistent_dir}/" 2>/dev/null || true
    rm -rf "${target}"
  fi

  ln -sfn "${persistent_dir}" "${target}"
}

restore_veeam_dpkg_state() {
  local info_dir="${VEEAM_OS_STATE_DIR}/dpkg/info"
  local status_dir="${VEEAM_OS_STATE_DIR}/dpkg/status.d"
  local status_file package

  if [[ -d "${info_dir}" ]]; then
    cp -a "${info_dir}/." /var/lib/dpkg/info/
  fi

  [[ -d "${status_dir}" ]] || return 0

  for status_file in "${status_dir}"/*.status; do
    [[ -f "${status_file}" && -s "${status_file}" ]] || continue
    package="$(awk '/^Package: / { print $2; exit }' "${status_file}")"
    [[ -n "${package}" ]] || continue

    if ! grep -q "^Package: ${package}$" /var/lib/dpkg/status; then
      {
        printf '\n'
        cat "${status_file}"
        printf '\n'
      } >>/var/lib/dpkg/status
    fi
  done
}

restore_veeam_systemd_state() {
  local units_dir="${VEEAM_OS_STATE_DIR}/systemd/units"
  local system_dir="${VEEAM_OS_STATE_DIR}/systemd/system"
  local enabled_units="${VEEAM_OS_STATE_DIR}/systemd/enabled-units"
  local unit

  if [[ -d "${units_dir}" ]]; then
    cp -a "${units_dir}/." /usr/lib/systemd/system/
  fi

  if [[ -d "${system_dir}" ]]; then
    cp -a "${system_dir}/." /etc/systemd/system/
  fi

  [[ -f "${enabled_units}" ]] || return 0

  while IFS= read -r unit; do
    [[ -n "${unit}" && -f "/usr/lib/systemd/system/${unit}" ]] || continue
    systemctl enable "${unit}" >/dev/null 2>&1 || true
  done <"${enabled_units}"
}

restore_veeam_os_state() {
  restore_veeam_accounts

  ensure_persistent_link /etc/veeam "${VEEAM_OS_STATE_DIR}/etc-veeam"
  ensure_persistent_link /var/lib/veeamdata "${VEEAM_OS_STATE_DIR}/var-lib-veeamdata"
  ensure_persistent_link /var/lib/veeam-usr-home "${VEEAM_OS_STATE_DIR}/var-lib-veeam-usr-home"

  restore_veeam_dpkg_state
  restore_veeam_systemd_state
}

generate_host_keys() {
  local generated=false
  if [[ ! -s "${HOST_KEY_DIR}/ssh_host_ed25519_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "${HOST_KEY_DIR}/ssh_host_ed25519_key"
    generated=true
  fi
  if [[ ! -s "${HOST_KEY_DIR}/ssh_host_ecdsa_key" ]]; then
    ssh-keygen -q -t ecdsa -b 521 -N '' -f "${HOST_KEY_DIR}/ssh_host_ecdsa_key"
    generated=true
  fi
  if [[ ! -s "${HOST_KEY_DIR}/ssh_host_rsa_key" ]]; then
    ssh-keygen -q -t rsa -b 4096 -N '' -f "${HOST_KEY_DIR}/ssh_host_rsa_key"
    generated=true
  fi

  chmod 0600 "${HOST_KEY_DIR}"/ssh_host_*_key
  chmod 0644 "${HOST_KEY_DIR}"/ssh_host_*_key.pub

  if [[ "${generated}" == true ]]; then
    log "Generated persistent SSH host keys in ${HOST_KEY_DIR}."
  else
    log "Using existing persistent SSH host keys from ${HOST_KEY_DIR}."
  fi
}

delete_previous_managed_user() {
  local previous_user
  previous_user="$(cat "${MANAGED_USER_FILE}" 2>/dev/null || true)"

  if [[ -n "${previous_user}" && "${previous_user}" != "${VEEAM_USERNAME}" ]]; then
    if id "${previous_user}" >/dev/null 2>&1; then
      log "Removing previously managed login account '${previous_user}'."
      userdel "${previous_user}"
    fi
  fi
}

ensure_group() {
  if getent group "${PGID}" >/dev/null 2>&1; then
    local existing_group
    existing_group="$(getent group "${PGID}" | cut -d: -f1)"

    if [[ "${existing_group}" == "ubuntu" && "${VEEAM_USERNAME}" != "ubuntu" ]] && ! getent group "${VEEAM_USERNAME}" >/dev/null 2>&1; then
      groupmod --new-name "${VEEAM_USERNAME}" "${existing_group}"
      printf '%s\n' "${VEEAM_USERNAME}"
      return
    fi

    printf '%s\n' "${existing_group}"
    return
  fi

  local group_name="${VEEAM_USERNAME}"
  if getent group "${group_name}" >/dev/null 2>&1; then
    group_name="${VEEAM_USERNAME}-${PGID}"
  fi

  groupadd --gid "${PGID}" "${group_name}"
  printf '%s\n' "${group_name}"
}

ensure_user() {
  local group_name
  group_name="$(ensure_group)"

  if id "${VEEAM_USERNAME}" >/dev/null 2>&1; then
    usermod --uid "${PUID}" --gid "${PGID}" --home "/home/${VEEAM_USERNAME}" --shell /bin/bash "${VEEAM_USERNAME}"
  else
    local existing_user
    existing_user="$(getent passwd "${PUID}" | cut -d: -f1 || true)"

    if [[ -n "${existing_user}" ]]; then
      if [[ "${existing_user}" == "ubuntu" ]]; then
        usermod \
          --login "${VEEAM_USERNAME}" \
          --gid "${PGID}" \
          --home "/home/${VEEAM_USERNAME}" \
          --move-home \
          --shell /bin/bash \
          "${existing_user}"
      else
        fail "PUID ${PUID} is already used by account '${existing_user}'. Choose a different PUID."
      fi
    else
      useradd --uid "${PUID}" --gid "${group_name}" --create-home --home-dir "/home/${VEEAM_USERNAME}" --shell /bin/bash "${VEEAM_USERNAME}"
    fi
  fi

  mkdir -p "/home/${VEEAM_USERNAME}/.ssh"
  chown -R "${VEEAM_USERNAME}:${PGID}" "/home/${VEEAM_USERNAME}"
  chmod 0700 "/home/${VEEAM_USERNAME}/.ssh"

  if [[ -n "${VEEAM_PASSWORD:-}" ]]; then
    printf '%s:%s\n' "${VEEAM_USERNAME}" "${VEEAM_PASSWORD}" | chpasswd
  else
    passwd -d "${VEEAM_USERNAME}" >/dev/null
  fi

  if [[ -n "${VEEAM_SSH_PUBLIC_KEY:-}" ]]; then
    printf '%s\n' "${VEEAM_SSH_PUBLIC_KEY}" >"/home/${VEEAM_USERNAME}/.ssh/authorized_keys"
    chown "${VEEAM_USERNAME}:${PGID}" "/home/${VEEAM_USERNAME}/.ssh/authorized_keys"
    chmod 0600 "/home/${VEEAM_USERNAME}/.ssh/authorized_keys"
  else
    rm -f "/home/${VEEAM_USERNAME}/.ssh/authorized_keys"
  fi

  printf '%s\n' "${VEEAM_USERNAME}" >"${MANAGED_USER_FILE}"
}

write_sudoers() {
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${VEEAM_USERNAME}" >"${SUDOERS_FILE}"
  chmod 0440 "${SUDOERS_FILE}"
  visudo -cf "${SUDOERS_FILE}" >/dev/null
}

write_sshd_config() {
  local password_auth=no
  if [[ -n "${VEEAM_PASSWORD:-}" ]]; then
    password_auth=yes
  fi

  cat >"${SSHD_CONFIG}" <<EOF
Port 22
Protocol 2
HostKey ${HOST_KEY_DIR}/ssh_host_ed25519_key
HostKey ${HOST_KEY_DIR}/ssh_host_ecdsa_key
HostKey ${HOST_KEY_DIR}/ssh_host_rsa_key
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication ${password_auth}
KbdInteractiveAuthentication no
UsePAM yes
AllowUsers ${VEEAM_USERNAME}
AuthorizedKeysFile .ssh/authorized_keys
PidFile /run/sshd.pid
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

  sshd -t -f "${SSHD_CONFIG}"
}

ensure_veeam_symlink() {
  mkdir -p /opt
  if [[ ! -L /opt/veeam ]]; then
    if [[ -e /opt/veeam ]]; then
      return
    fi
    ln -sfn "${VEEAM_DIR}" /opt/veeam
  fi
}

main() {
  validate_env
  prepare_directories
  restore_veeam_os_state
  generate_host_keys
  delete_previous_managed_user
  ensure_user
  write_sudoers
  write_sshd_config

  log "Configured managed user '${VEEAM_USERNAME}' with UID ${PUID} and GID ${PGID}."
  log "Password authentication is $(if [[ -n "${VEEAM_PASSWORD:-}" ]]; then printf enabled; else printf disabled; fi)."
  log "Public key authentication is $(if [[ -n "${VEEAM_SSH_PUBLIC_KEY:-}" ]]; then printf configured; else printf not-configured; fi)."
  log "Starting systemd as PID 1."

  exec "$@"
}

main "$@"
