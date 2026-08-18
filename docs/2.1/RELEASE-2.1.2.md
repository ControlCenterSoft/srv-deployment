# Control Center 2.1.2 — Minecraft status visibility repair

## Problem reproduced

The Minecraft management commands can execute, but the UI can lose the server state after a stop operation and the user cannot clearly see whether start/stop/restart actually succeeded.

The root cause is in the frozen 2.1.0/2.1.1 control chain. The legacy status backend discovers the runtime primarily from a live `bedrock_server` PID and then checks only several conventional fallback paths. The accepted production runtime is `/opt/minicraft`. When the canonical service is stopped there is no live PID and `/opt/minicraft` is not one of those fallback candidates, so the status backend can raise `Bedrock runtime was not found` instead of returning a valid OFFLINE state.

The production service evidence confirms the canonical unit has `WorkingDirectory=/opt/minicraft`.

## 2.1.2 repair

2.1.2 does not modify frozen 2.1.0 or 2.1.1.

It adds a new public 2.1.2 Minecraft dispatcher that treats `srv-control-minecraft-bedrock.service` as the authoritative source of runtime identity:

- runtime comes from systemd `WorkingDirectory`, not from a running PID;
- `status` always returns a structured state for installed canonical service, including while stopped;
- state is explicitly `running`, `degraded`, `stopped`, or `error`;
- start/stop/restart waits for the requested final state and returns a human-readable confirmed result;
- start/restart confirms ONLINE, UDP listener, PID and active world;
- stop confirms OFFLINE while retaining runtime/world metadata;
- mature non-status operations continue through frozen 2.1.1 delegates.

The Control Center page also receives a small 2.1.2 live-status layer:

- direct status polling every 5 seconds;
- persistent ONLINE/OFFLINE/DEGRADED badge;
- PID, UDP port, world, version and last check;
- persistent last-command result;
- start/restart/stop buttons follow the current service state.

## Safety

- `srv-control.service` keeps `NoNewPrivileges=true`.
- The 2.1.1 root action-agent privilege bridge remains authoritative.
- No world replacement or runtime reinstall is performed.
- Existing 2.1.1 helpers are frozen as delegates and can be restored transactionally.
- Rollback restores the exact pre-2.1.2 UI/helper files and unwinds 2.1.1 as well when 2.1.2 was installed directly from an older accepted source.

## Real-server acceptance

If the server is running when acceptance begins, acceptance performs one controlled stop/status/start cycle. The critical gate is that `srv-control-minecraft status` must still return `ok=true`, `active=false`, `state=stopped`, the canonical runtime and active world while no Bedrock PID exists. The original running/stopped state is preserved.
