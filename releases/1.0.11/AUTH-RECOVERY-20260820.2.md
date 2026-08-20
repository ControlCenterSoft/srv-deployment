# Authentication recovery hotfix — build 20260820.2

Observed symptom after a successful update to 1.0.11/20260820.1:

```text
Служба авторизации недоступна: [Errno 2] No such file or directory
```

The Web process connects to `/run/control-center-auth/auth.sock`. The incident proves that the Web service could remain available while the isolated authentication daemon/socket was unavailable.

Build 20260820.2 changes the runtime contract:

- `control-center.service` requires `control-center-authd.service`;
- Web startup waits for a root:control-center mode 0660 auth socket;
- authd uses `Restart=always` and a systemd-managed runtime directory;
- authd polls and rebinds `auth.sock` if the pathname is removed while the process is alive;
- installer acceptance deliberately removes authd/socket and proves automatic recovery from starting only the Web service;
- installer probes the socket as the unprivileged `control-center` identity before declaring success.
