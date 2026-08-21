#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

INSTALL_ROOT="${CONTROL_CENTER_INSTALL_ROOT:-/usr/local/lib/control-center}"
CURRENT_LINK="$INSTALL_ROOT/current"
CURRENT_BIN="$CURRENT_LINK/control-center"
WORKER_SERVICE="${CONTROL_CENTER_WORKER_SERVICE:-control-center-privileged-worker.service}"
WORKER_UNIT_PATH="${CONTROL_CENTER_WORKER_UNIT_PATH:-/etc/systemd/system/control-center-privileged-worker.service}"
STATE_DIR="${CONTROL_CENTER_MIGRATION_STATE_DIR:-/var/lib/control-center/platform-migrations}"
EXPECTED_CURRENT_VERSION="${CONTROL_CENTER_EXPECTED_MIGRATION_FROM:-1.0.0}"
EXPECTED_CURRENT_COMMIT="${CONTROL_CENTER_EXPECTED_MIGRATION_COMMIT:-1b364ae88789696bf98537d21544de8a259d086d}"

log() { printf '[control-center-migrate-v2] %s\n' "$*"; }
die() { printf '[control-center-migrate-v2] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "migration must run as root"
for cmd in systemctl install sha256sum stat mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required"
done
[[ -d /run/systemd/system ]] || die "systemd is not running"
[[ -L "$CURRENT_LINK" ]] || die "current release link is missing"
[[ -x "$CURRENT_BIN" ]] || die "current trusted runtime is missing"
systemctl cat control-center.service >/dev/null 2>&1 || die "main Control Center service is not installed"

current_version="$("$CURRENT_BIN" build-info --field version)" || die "current runtime cannot report version"
current_commit="$("$CURRENT_BIN" build-info --field commit)" || die "current runtime cannot report commit"
[[ "$current_version" == "$EXPECTED_CURRENT_VERSION" ]] \
  || die "migration is allowed only from $EXPECTED_CURRENT_VERSION; current=$current_version"
[[ "$current_commit" == "$EXPECTED_CURRENT_COMMIT" ]] \
  || die "migration source commit rejected: current=$current_commit"

# A 1.0.0 host must not have an active privileged worker before the signed
# dual-runtime release is switched in. This prevents an ExecStart target from
# resolving to an incomplete or untrusted release layout.
if systemctl is-active --quiet "$WORKER_SERVICE" 2>/dev/null; then
  die "privileged worker is unexpectedly active before platform-v2 migration"
fi

work="$(mktemp -d /tmp/control-center-platform-v2.XXXXXX)"
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT

UNIT_SOURCE="$work/control-center-privileged-worker.service"
cat > "$UNIT_SOURCE" <<'UNIT'
[Unit]
Description=Control Center privileged typed-operation worker
After=local-fs.target
Before=control-center.service

[Service]
Type=simple
User=root
Group=root
Environment=CONTROL_CENTER_ALLOWED_USER=control-center
Environment=CONTROL_CENTER_ALLOWED_SERVICES=control-center.service
Environment=CONTROL_CENTER_PRIVILEGED_SOCKET=/run/control-center/privileged-worker.sock
Environment=CONTROL_CENTER_PRIVILEGED_AUDIT=/var/log/control-center-privileged/audit.jsonl
EnvironmentFile=-/etc/control-center/privileged-worker.env
ExecStart=/usr/local/lib/control-center/current/control-center-privileged-worker
Restart=on-failure
RestartSec=2s
TimeoutStartSec=15s
TimeoutStopSec=10s
RuntimeDirectory=control-center
RuntimeDirectoryMode=0755
LogsDirectory=control-center-privileged
LogsDirectoryMode=0700
UMask=0077
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
RestrictSUIDSGID=yes
RestrictRealtime=yes
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX
SystemCallArchitectures=native
ReadWritePaths=/run/control-center /var/log/control-center-privileged

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 "$UNIT_SOURCE"
unit_sha="$(sha256sum "$UNIT_SOURCE" | awk '{print $1}')"
[[ "$unit_sha" =~ ^[0-9a-f]{64}$ ]] || die "unable to identify migration unit"

created_unit=0
rollback() {
  rc=$?
  trap - ERR
  if (( created_unit )); then
    rm -f -- "$WORKER_UNIT_PATH"
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap rollback ERR

if [[ -e "$WORKER_UNIT_PATH" ]]; then
  [[ -f "$WORKER_UNIT_PATH" && ! -L "$WORKER_UNIT_PATH" ]] || die "existing worker unit path is not a regular file"
  existing_sha="$(sha256sum "$WORKER_UNIT_PATH" | awk '{print $1}')"
  [[ "$existing_sha" == "$unit_sha" ]] || die "existing worker unit differs from authenticated platform-v2 contract"
  log "worker platform unit already matches migration contract"
else
  install -D -o root -g root -m 0644 "$UNIT_SOURCE" "$WORKER_UNIT_PATH"
  created_unit=1
  log "installed authenticated privileged-worker platform unit for direct migration"
fi

systemctl daemon-reload
systemctl cat "$WORKER_SERVICE" >/dev/null 2>&1 \
  || die "privileged worker systemd unit migration failed: $WORKER_SERVICE"
if systemctl is-active --quiet "$WORKER_SERVICE" 2>/dev/null; then
  die "privileged worker became active before signed dual-runtime switch"
fi
if systemctl is-enabled --quiet "$WORKER_SERVICE" 2>/dev/null; then
  die "privileged worker became enabled before signed dual-runtime switch"
fi

install -d -o root -g root -m 0700 "$STATE_DIR"
state_tmp="$work/platform-v2.json"
printf '{\n' > "$state_tmp"
printf '  "schema": 1,\n' >> "$state_tmp"
printf '  "migration": "platform-v2-worker-unit",\n' >> "$state_tmp"
printf '  "source_version": "%s",\n' "$current_version" >> "$state_tmp"
printf '  "source_commit": "%s",\n' "$current_commit" >> "$state_tmp"
printf '  "worker_unit_sha256": "%s",\n' "$unit_sha" >> "$state_tmp"
printf '  "worker_started": false\n' >> "$state_tmp"
printf '}\n' >> "$state_tmp"
install -o root -g root -m 0600 "$state_tmp" "$STATE_DIR/platform-v2.json"

trap - ERR
log "migration completed; worker unit installed but intentionally not started before signed dual-runtime switch"
printf 'PLATFORM_V2_MIGRATION=PASSED\n'
printf 'SOURCE_VERSION=%s\n' "$current_version"
printf 'SOURCE_COMMIT=%s\n' "$current_commit"
printf 'WORKER_UNIT_INSTALLED=true\n'
printf 'WORKER_ACTIVATED=false\n'
