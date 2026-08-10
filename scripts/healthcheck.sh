#!/usr/bin/env bash
set -Eeuo pipefail

SSHD_CONFIG=/run/virtual-veeam-file-server/sshd_config
VEEAM_LINK=/opt/veeam
VEEAM_CONFIG_DIR=/config/veeam
VEEAM_DEPLOYMENT_SOCKET=/run/veeam/veeamdeploymentCli
VEEAM_ENVIRONMENT_SOCKET=/run/veeamenvironment/socket
VEEAM_TRANSPORT_SOCKET=/run/veeamtransport/veeamtransport.sock

fail() {
  echo "$*" >&2
  exit 1
}

unit_exists() {
  local unit="${1}"

  systemctl list-unit-files --plain --no-legend "${unit}" 2>/dev/null \
    | awk '{print $1}' \
    | grep -Fxq "${unit}"
}

require_active_unit() {
  local unit="${1}"

  systemctl is-active --quiet "${unit}" || fail "${unit} is installed but not active"
}

require_socket() {
  local socket_path="${1}"
  local description="${2}"

  [[ -S "${socket_path}" ]] || fail "${description} socket is missing: ${socket_path}"
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || fail "systemctl is not available"
  [[ "$(cat /proc/1/comm)" == "systemd" ]] || fail "systemd is not PID 1"

  local state
  state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ "${state}" == "running" ]] || fail "systemd is not fully running: ${state:-unknown}"

  local failed_units
  failed_units="$(systemctl --failed --plain --no-legend 2>/dev/null | awk '{print $1}' | xargs)"
  [[ -z "${failed_units}" ]] || fail "systemd has failed units: ${failed_units}"
}

if ! pgrep -x sshd >/dev/null 2>&1; then
  fail "sshd is not running"
fi

[[ -f "${SSHD_CONFIG}" ]] || fail "sshd configuration is missing: ${SSHD_CONFIG}"
sshd -t -f "${SSHD_CONFIG}" >/dev/null 2>&1 || fail "sshd configuration is invalid"

[[ -L "${VEEAM_LINK}" ]] || fail "${VEEAM_LINK} is not a symlink"
[[ "$(readlink "${VEEAM_LINK}")" == "${VEEAM_CONFIG_DIR}" ]] \
  || fail "${VEEAM_LINK} does not point to ${VEEAM_CONFIG_DIR}"

require_systemd
require_active_unit virtual-veeam-sshd.service

if unit_exists veeamdeployment.service; then
  require_active_unit veeamdeployment.service
  require_socket "${VEEAM_DEPLOYMENT_SOCKET}" "Veeam deployment service"
fi

if unit_exists veeamenvironment.service; then
  require_active_unit veeamenvironment.service
  require_socket "${VEEAM_ENVIRONMENT_SOCKET}" "Veeam environment service"
fi

if unit_exists veeamtransport.service; then
  require_active_unit veeamtransport.service
  require_socket "${VEEAM_TRANSPORT_SOCKET}" "Veeam transport service"
fi

exit 0
