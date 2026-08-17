#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/apply.sh"
TMP="$(mktemp "${RELEASE_DIR}/.apply-1.3.2.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-1.3.2"

legacy_timer_enabled="$(systemctl is-enabled minecraft-update.timer 2>/dev/null || true)"
legacy_timer_active="$(systemctl is-active minecraft-update.timer 2>/dev/null || true)"
modern_timer_enabled="$(systemctl is-enabled srv-control-minecraft-auto-update.timer 2>/dev/null || true)"
modern_timer_active="$(systemctl is-active srv-control-minecraft-auto-update.timer 2>/dev/null || true)"

cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
if 'RELEASE_ID="1.3.0"' not in text or 'RELEASE_VERSION="1.3.0"' not in text:
    raise SystemExit("apply 1.3.2 release anchors missing")
text = text.replace("1.3.0", "1.3.2")
target.write_text(text, encoding="utf-8")
PY

chmod 0700 "$TMP"
bash "$TMP" "$@"

# Preserve timer state for rollback after the base apply has created the release backup.
install -d -m 0750 "$BACKUP_DIR/state"
printf '%s\n' "$legacy_timer_enabled" > "$BACKUP_DIR/state/minecraft-update.timer.enabled.before-1.3.2"
printf '%s\n' "$legacy_timer_active" > "$BACKUP_DIR/state/minecraft-update.timer.active.before-1.3.2"
printf '%s\n' "$modern_timer_enabled" > "$BACKUP_DIR/state/srv-control-minecraft-auto-update.timer.enabled.before-1.3.2"
printf '%s\n' "$modern_timer_active" > "$BACKUP_DIR/state/srv-control-minecraft-auto-update.timer.active.before-1.3.2"
chmod 0640 "$BACKUP_DIR/state/"*"minecraft"* 2>/dev/null || true

# Restore the exact legacy sudo contract used by the stable Minecraft implementation.
install -m 0440 -o root -g root \
    "$RELEASE_DIR/system/sudoers-srv-control-minecraft-legacy" \
    /etc/sudoers.d/srv-control-minecraft-legacy
/usr/sbin/visudo -cf /etc/sudoers.d/srv-control-minecraft-legacy >/dev/null

# The old updater is the authoritative updater again. The 1.3.x multi-instance
# updater is intentionally disabled to prevent two independent mechanisms from
# modifying the same Bedrock runtime.
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl enable --now minecraft-update.timer
fi

printf 'MINECRAFT BACKEND PASS: legacy helpers restored, modern auto-updater disabled\n'
