#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCT="control-center"
APP_USER="control-center"
APP_GROUP="control-center"
BASE_DIR="/opt/control-center"
RELEASES_DIR="${BASE_DIR}/releases"
CURRENT_LINK="${BASE_DIR}/current"
PREVIOUS_LINK="${BASE_DIR}/previous"
SERVICE_NAME="control-center-api.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MANIFEST="${ROOT_DIR}/deployment.json"
MODE="install"
STAGING_DIR=""

usage() {
  cat <<'EOF'
Usage: install/install.sh [--preflight|--install|--repair|--rollback]

  --preflight  Validate host prerequisites only.
  --install    Install/switch to this checkout atomically (default).
  --repair     Re-apply service configuration and current release safely.
  --rollback   Switch atomically to the previously active release.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]]; then
    rm -rf -- "${STAGING_DIR}"
  fi
}
trap cleanup EXIT

for arg in "$@"; do
  case "${arg}" in
    --preflight) MODE="preflight" ;;
    --install) MODE="install" ;;
    --repair) MODE="repair" ;;
    --rollback) MODE="rollback" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: ${arg}" ;;
  esac
done

preflight() {
  [[ "${EUID}" -eq 0 ]] || die "installer must run as root"
  [[ -f "${MANIFEST}" ]] || die "deployment.json is missing"
  [[ -f "${ROOT_DIR}/api/server.py" ]] || die "api/server.py is missing"
  [[ -f "${ROOT_DIR}/install/control-center-api.service" ]] || die "systemd unit template is missing"

  local command
  for command in python3 systemctl useradd groupadd getent install cp mv ln readlink sha256sum awk mktemp rm chmod chown; do
    command -v "${command}" >/dev/null 2>&1 || die "required command is missing: ${command}"
  done

  python3 "${ROOT_DIR}/scripts/validate_deployment.py" "${MANIFEST}" >/dev/null
  log "Preflight OK."
}

ensure_identity() {
  if ! getent group "${APP_GROUP}" >/dev/null 2>&1; then
    groupadd --system "${APP_GROUP}"
  fi
  if ! getent passwd "${APP_USER}" >/dev/null 2>&1; then
    useradd \
      --system \
      --gid "${APP_GROUP}" \
      --home-dir "${BASE_DIR}" \
      --shell /usr/sbin/nologin \
      "${APP_USER}"
  fi
}

manifest_version() {
  python3 - "${MANIFEST}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
print(data["release"]["version"])
PY
}

source_id() {
  if command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR}" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "${ROOT_DIR}" rev-parse HEAD
    return
  fi
  {
    sha256sum "${ROOT_DIR}/deployment.json"
    sha256sum "${ROOT_DIR}/api/server.py"
    sha256sum "${ROOT_DIR}/install/control-center-api.service"
  } | sha256sum | awk '{print $1}'
}

safe_release_id() {
  local version sha
  version="$(manifest_version)"
  sha="$(source_id)"
  [[ "${version}" =~ ^[0-9A-Za-z._+-]+$ ]] || die "unsafe release version"
  [[ "${sha}" =~ ^[0-9a-fA-F]{12,}$ ]] || die "unsafe source id"
  printf '%s-%s\n' "${version}" "${sha:0:12}"
}

atomic_link() {
  local target="$1" link="$2" temporary="${link}.new"
  rm -f -- "${temporary}"
  ln -s -- "${target}" "${temporary}"
  mv -Tf -- "${temporary}" "${link}"
}

health_check() {
  python3 - <<'PY'
import json
import time
from urllib.error import URLError
from urllib.request import urlopen

for _ in range(40):
    try:
        with urlopen("http://127.0.0.1:8876/api/v1/readiness", timeout=1.0) as response:
            data = json.load(response)
            if response.status == 200 and data.get("status") == "ready":
                raise SystemExit(0)
    except (OSError, URLError, ValueError):
        pass
    time.sleep(0.25)
raise SystemExit(1)
PY
}

install_service_file() {
  install -o root -g root -m 0644 \
    "${ROOT_DIR}/install/control-center-api.service" \
    "${SERVICE_PATH}"
  systemctl daemon-reload
}

restore_after_failed_switch() {
  local old_target="$1"
  log "New release failed readiness; restoring previous state."
  if [[ -n "${old_target}" && -d "${old_target}" ]]; then
    atomic_link "${old_target}" "${CURRENT_LINK}"
    systemctl restart "${SERVICE_NAME}" || true
  else
    rm -f -- "${CURRENT_LINK}"
    systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}

install_or_repair() {
  ensure_identity
  install -d -o root -g "${APP_GROUP}" -m 0750 "${BASE_DIR}" "${RELEASES_DIR}"

  local release_id release_dir old_target=""
  release_id="$(safe_release_id)"
  release_dir="${RELEASES_DIR}/${release_id}"
  if [[ -L "${CURRENT_LINK}" ]]; then
    old_target="$(readlink -f -- "${CURRENT_LINK}" || true)"
  fi

  if [[ ! -d "${release_dir}" ]]; then
    STAGING_DIR="$(mktemp -d "${BASE_DIR}/.staging.XXXXXX")"
    chown root:"${APP_GROUP}" "${STAGING_DIR}"
    chmod 0750 "${STAGING_DIR}"
    install -d -o root -g "${APP_GROUP}" -m 0750 "${STAGING_DIR}/api"
    install -o root -g "${APP_GROUP}" -m 0640 \
      "${ROOT_DIR}/api/__init__.py" \
      "${ROOT_DIR}/api/server.py" \
      "${STAGING_DIR}/api/"
    install -o root -g "${APP_GROUP}" -m 0640 \
      "${ROOT_DIR}/deployment.json" \
      "${STAGING_DIR}/deployment.json"
    if [[ -f "${ROOT_DIR}/README.md" ]]; then
      install -o root -g "${APP_GROUP}" -m 0640 \
        "${ROOT_DIR}/README.md" \
        "${STAGING_DIR}/README.md"
    fi
    mv -- "${STAGING_DIR}" "${release_dir}"
    STAGING_DIR=""
  fi

  install_service_file

  if [[ -n "${old_target}" && "${old_target}" != "${release_dir}" && -d "${old_target}" ]]; then
    atomic_link "${old_target}" "${PREVIOUS_LINK}"
  fi
  atomic_link "${release_dir}" "${CURRENT_LINK}"

  if ! systemctl enable --now "${SERVICE_NAME}"; then
    restore_after_failed_switch "${old_target}"
    die "systemd could not start ${SERVICE_NAME}"
  fi
  if ! health_check; then
    restore_after_failed_switch "${old_target}"
    die "readiness check failed"
  fi

  log "Control Center installed successfully."
  log "Release: ${release_id}"
  log "Current: ${release_dir}"
  log "API: http://127.0.0.1:8876/api/v1/health"
}

rollback_release() {
  ensure_identity
  [[ -L "${PREVIOUS_LINK}" ]] || die "previous release is not available"
  local previous_target current_target=""
  previous_target="$(readlink -f -- "${PREVIOUS_LINK}" || true)"
  [[ -n "${previous_target}" && -d "${previous_target}" ]] || die "previous release target is invalid"
  if [[ -L "${CURRENT_LINK}" ]]; then
    current_target="$(readlink -f -- "${CURRENT_LINK}" || true)"
  fi

  atomic_link "${previous_target}" "${CURRENT_LINK}"
  if [[ -n "${current_target}" && -d "${current_target}" ]]; then
    atomic_link "${current_target}" "${PREVIOUS_LINK}"
  fi

  install_service_file
  if ! systemctl enable --now "${SERVICE_NAME}" || ! health_check; then
    if [[ -n "${current_target}" && -d "${current_target}" ]]; then
      atomic_link "${current_target}" "${CURRENT_LINK}"
      atomic_link "${previous_target}" "${PREVIOUS_LINK}"
      systemctl restart "${SERVICE_NAME}" || true
    fi
    die "rollback target failed readiness; original release restored"
  fi

  log "Rollback successful."
  log "Current: ${previous_target}"
}

preflight
case "${MODE}" in
  preflight) exit 0 ;;
  install|repair) install_or_repair ;;
  rollback) rollback_release ;;
esac
