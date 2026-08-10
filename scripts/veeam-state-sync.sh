#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${VEEAM_OS_STATE_DIR:-/config/veeam-os}"

copy_tree() {
  local source="${1}"
  local target="${2}"

  [[ -d "${source}" ]] || return 0
  mkdir -p "${target}"

  if [[ "$(readlink -f "${source}")" == "$(readlink -f "${target}")" ]]; then
    return 0
  fi

  cp -a "${source}/." "${target}/"
}

sync_accounts() {
  mkdir -p "${STATE_DIR}/accounts"

  getent passwd | awk -F: '$1 ~ /^veeam-usr-/' >"${STATE_DIR}/accounts/passwd"
  getent group | awk -F: '$1 ~ /^veeam-grp-/ || $1 ~ /^veeam-usr-/' >"${STATE_DIR}/accounts/group"
}

sync_dpkg_state() {
  local package

  mkdir -p "${STATE_DIR}/dpkg/info" "${STATE_DIR}/dpkg/status.d"
  : >"${STATE_DIR}/dpkg/packages.list"

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    printf '%s\n' "${package}" >>"${STATE_DIR}/dpkg/packages.list"

    find /var/lib/dpkg/info -maxdepth 1 -type f -name "${package}.*" -exec cp -a {} "${STATE_DIR}/dpkg/info/" \;

    awk -v package="${package}" '
      BEGIN { RS = ""; ORS = "\n\n" }
      {
        split($0, lines, "\n")
        if (lines[1] == "Package: " package) {
          print
        }
      }
    ' /var/lib/dpkg/status >"${STATE_DIR}/dpkg/status.d/${package}.status"
  done < <(
    dpkg-query -W -f='${binary:Package}\n' 2>/dev/null \
      | grep -E '^(veeam|openssl-fips|dell-ddboost-sdk|hpe-catalyst-client|netapp-snapdiffv3)' \
      | sort -u
  )
}

sync_systemd_state() {
  mkdir -p "${STATE_DIR}/systemd/units" "${STATE_DIR}/systemd/system"

  find /usr/lib/systemd/system /lib/systemd/system \
    -maxdepth 1 -type f -name 'veeam*.service' \
    -exec cp -a {} "${STATE_DIR}/systemd/units/" \; 2>/dev/null || true

  find /etc/systemd/system \
    -maxdepth 1 -type d -name 'veeam*.service.d' \
    -exec cp -a {} "${STATE_DIR}/systemd/system/" \; 2>/dev/null || true

  systemctl list-unit-files --plain --no-legend 'veeam*.service' 2>/dev/null \
    | awk '$2 == "enabled" { print $1 }' \
    | sort -u >"${STATE_DIR}/systemd/enabled-units"
}

main() {
  mkdir -p "${STATE_DIR}"

  copy_tree /etc/veeam "${STATE_DIR}/etc-veeam"
  copy_tree /var/lib/veeamdata "${STATE_DIR}/var-lib-veeamdata"
  copy_tree /var/lib/veeam-usr-home "${STATE_DIR}/var-lib-veeam-usr-home"

  sync_accounts
  sync_dpkg_state
  sync_systemd_state
}

main "$@"
