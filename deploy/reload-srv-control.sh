#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-srv-control.service}"
HEALTH_URL="${2:-http://127.0.0.1:8876/api/v1/health}"
GRACE_SECONDS="${SRVCC_RELOAD_GRACE_SECONDS:-30}"
FORCE_SECONDS="${SRVCC_RELOAD_FORCE_SECONDS:-10}"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

wait_health() {
    python3 - "$HEALTH_URL" <<'PY'
import json
import sys
import time
import urllib.request

url = sys.argv[1]
last_error = None

for _ in range(30):
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            payload = json.load(response)

        if payload.get("ok") is True:
            raise SystemExit(0)

        last_error = f"unexpected payload: {payload!r}"

    except Exception as exc:
        last_error = repr(exc)

    time.sleep(1)

raise SystemExit(f"health did not recover: {last_error}")
PY
}

manager_pid() {
    systemctl show "$SERVICE" -p MainPID --value 2>/dev/null
}

worker_pids() {
    local parent="$1"

    ps -eo pid=,ppid=,stat=,args= \
        | awk -v parent="$parent" '
            $2 == parent && $3 !~ /^Z/ && index($0, "--multiprocessing-fork") { print $1 }
        '
}

remaining_pids() {
    local pid parent row ppid stat args
    parent="$(manager_pid)"

    for pid in "$@"; do
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue

        row="$(ps -o ppid=,stat=,args= -p "$pid" 2>/dev/null || true)"
        [[ -n "$row" ]] || continue

        ppid="$(awk '{print $1}' <<< "$row")"
        stat="$(awk '{print $2}' <<< "$row")"
        args="$(cut -d' ' -f3- <<< "$(sed -E 's/^[[:space:]]+//' <<< "$row")")"

        # A zombie has already exited; it only awaits reaping by its parent and
        # must not make a successful worker rotation look like a failure.
        [[ "$stat" == Z* ]] && continue

        # PID reuse must not be mistaken for a stale Uvicorn worker.
        [[ "$ppid" == "$parent" ]] || continue
        [[ "$args" == *"--multiprocessing-fork"* ]] || continue

        printf '%s\n' "$pid"
    done
}

wait_old_workers() {
    local timeout="$1"
    shift
    local -a old=("$@")
    local deadline=$((SECONDS + timeout))
    local -a remaining=()

    while (( SECONDS < deadline )); do
        mapfile -t remaining < <(remaining_pids "${old[@]}")

        if (( ${#remaining[@]} == 0 )); then
            return 0
        fi

        sleep 1
    done

    mapfile -t remaining < <(remaining_pids "${old[@]}")

    if (( ${#remaining[@]} == 0 )); then
        return 0
    fi

    printf '%s\n' "${remaining[@]}"
    return 1
}

wait_worker_count() {
    local parent="$1"
    local wanted="$2"
    local deadline=$((SECONDS + 30))
    local count

    while (( SECONDS < deadline )); do
        count="$(worker_pids "$parent" | wc -l | tr -d ' ')"

        if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= wanted )); then
            return 0
        fi

        sleep 1
    done

    return 1
}

if ! systemctl is-active --quiet "$SERVICE"; then
    log "RELOAD: service is not active; starting"
    systemctl start "$SERVICE"
    wait_health
    log "RELOAD PASS: service started"
    exit 0
fi

exec_start="$(systemctl show "$SERVICE" -p ExecStart --value 2>/dev/null || true)"

if [[ "$exec_start" == *"--workers 2"* ]]; then
    parent="$(manager_pid)"

    if [[ ! "$parent" =~ ^[1-9][0-9]*$ ]]; then
        log "RELOAD FAIL: unable to resolve Uvicorn manager PID"
        exit 1
    fi

    mapfile -t old_workers < <(worker_pids "$parent")

    log "RELOAD: sending SIGHUP to Uvicorn manager ${parent}; old workers: ${old_workers[*]:-none}"
    systemctl kill --kill-who=main --signal=HUP "$SERVICE"
    wait_health

    if (( ${#old_workers[@]} > 0 )); then
        if ! stale="$(wait_old_workers "$GRACE_SECONDS" "${old_workers[@]}")"; then
            mapfile -t stale_workers <<< "$stale"
            log "RELOAD: graceful timeout; terminating stale workers: ${stale_workers[*]}"
            kill -TERM "${stale_workers[@]}" 2>/dev/null || true

            if ! stale="$(wait_old_workers "$FORCE_SECONDS" "${stale_workers[@]}")"; then
                mapfile -t stale_workers <<< "$stale"
                log "RELOAD: TERM timeout; killing stale workers: ${stale_workers[*]}"
                kill -KILL "${stale_workers[@]}" 2>/dev/null || true
                sleep 1
            fi
        fi
    fi

    wait_worker_count "$parent" 2 \
        || { log "RELOAD FAIL: Uvicorn did not restore two workers"; exit 1; }

    wait_health

    mapfile -t stale_after < <(remaining_pids "${old_workers[@]}")
    if (( ${#stale_after[@]} > 0 )); then
        log "RELOAD FAIL: stale workers remain after bounded rotation: ${stale_after[*]}"
        exit 1
    fi

    log "RELOAD PASS: bounded worker rotation completed without stopping listener"
    exit 0
fi

log "RELOAD: legacy single-process service detected; using one-time restart"
systemctl restart "$SERVICE"
wait_health
log "RELOAD PASS: legacy service restarted"
