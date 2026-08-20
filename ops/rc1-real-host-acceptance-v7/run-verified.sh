#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'ERROR: rc.1 v7 acceptance must run as root' >&2; exit 1; }

V6_LAUNCHER_COMMIT="9b0ae387a9ebd3cd834de170c391f56bb2c3a68e"
V6_LAUNCHER_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${V6_LAUNCHER_COMMIT}/ops/rc1-real-host-acceptance-v6-resume/run-verified.sh"
V6_LAUNCHER_SHA256="869864257f6ff594dee68c7afeecc4e756783e4c7e00ab0b99c54547077ad83c"
V6_SCRIPT_SHA256="b845558e4172ab4e82fd5ad85dfce88377f767e5bfef16dc9b9f1b48255a2ae9"
V7_SCRIPT_SHA256="fcbaac43459b0ef9fffe239c56961201bc514d8d14cf02f9df4f423ad94e80d4"
WORK="$(mktemp -d /tmp/control-center-rc1-v7-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$V6_LAUNCHER_URL" -o "$WORK/v6-launcher.sh"
printf '%s  %s\n' "$V6_LAUNCHER_SHA256" "$WORK/v6-launcher.sh" | sha256sum -c -

python3 - "$WORK/v6-launcher.sh" "$WORK/v6-builder.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
old='''if [[ ${RC1_V6_BUILD_ONLY:-0} == 1 ]]; then\n  printf 'V6_BUILD_ONLY=PASSED\\nV6_SHA256=%s\\n' "$V6_SCRIPT_SHA256"\n  exit 0\nfi\n\nexec bash "$WORK/v6.sh" --continue-after-upgrade\n'''
new='''cp "$WORK/v6.sh" "$OUTPUT_V6"\nprintf 'V6_BUILDER=PASSED\\n'\n'''
if src.count(old) != 1:
    raise SystemExit('ERROR: immutable v6 launcher final contract mismatch')
Path(sys.argv[2]).write_text(src.replace(old,new,1))
PY
chmod 0700 "$WORK/v6-builder.sh"
OUTPUT_V6="$WORK/v6.sh" bash "$WORK/v6-builder.sh"
printf '%s  %s\n' "$V6_SCRIPT_SHA256" "$WORK/v6.sh" | sha256sum -c -

python3 - "$WORK/v6.sh" "$WORK/v7.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()

# Final candidate identity.
src=src.replace('RC_COMMIT="2b104ffa69d5f11b1a4de24fe92be95d89422acd"','RC_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"',1)
src=src.replace('RC_AMD64_SHA256="0ecdfd3d44a2d5ba58d2d221527765e4014a0fa4fc62b7e73ac06718fb3a5121"','RC_AMD64_SHA256="dd1bae6364657c1f65a72c63e428f61df58d0030ee85b5320ede6a598a6a6c1d"',1)
src=src.replace('RC_ARM64_SHA256="232393b745f0b649126a891f262d469a45eac97340856b1ce2952934780dbe74"','RC_ARM64_SHA256="fadd38f5211442073a071a3d87cad35bc1f4f89c0e3466a36861f40dbbf8f54e"',1)

anchor='BETA_COMMIT="b3b7cd7d3a1985bbe02b392bce5e26d5bf0cf39c"\n'
insert=anchor+'PRIOR_RC_COMMIT="2b104ffa69d5f11b1a4de24fe92be95d89422acd"\nPRIOR_RC_AMD64_SHA256="0ecdfd3d44a2d5ba58d2d221527765e4014a0fa4fc62b7e73ac06718fb3a5121"\nPRIOR_RC_ARM64_SHA256="232393b745f0b649126a891f262d469a45eac97340856b1ce2952934780dbe74"\n'
if src.count(anchor) != 1: raise SystemExit('ERROR: beta constant anchor mismatch')
src=src.replace(anchor,insert,1)
src=src.replace('RC_PACKAGE="$BASE/control-center-1.0.0-rc.1.tar.gz"','RC_PACKAGE="$BASE/control-center-1.0.0-rc.1.tar.gz"\nBETA_PACKAGE="$BASE/control-center-accepted-beta.1.tar.gz"',1)
src=src.replace('EXPECTED_RC_SHA=""','EXPECTED_RC_SHA=""\nEXPECTED_PRIOR_RC_SHA=""',1)

root_anchor='[[ $EUID -eq 0 ]] || { printf \'ERROR: rc.1 real-host acceptance must run as root\\n\' >&2; exit 1; }\n'
if src.count(root_anchor) != 1: raise SystemExit('ERROR: root anchor mismatch')
src=src.replace(root_anchor,root_anchor+'export HOME="${HOME:-/root}"\nexport GIT_TERMINAL_PROMPT=0\n',1)

src=src.replace('x86_64) GOARCH=amd64; EXPECTED_RC_SHA="$RC_AMD64_SHA256"; GO_ARCHIVE_SHA="$GO_AMD64_SHA256" ;;','x86_64) GOARCH=amd64; EXPECTED_RC_SHA="$RC_AMD64_SHA256"; EXPECTED_PRIOR_RC_SHA="$PRIOR_RC_AMD64_SHA256"; GO_ARCHIVE_SHA="$GO_AMD64_SHA256" ;;',1)
src=src.replace('aarch64|arm64) GOARCH=arm64; EXPECTED_RC_SHA="$RC_ARM64_SHA256"; GO_ARCHIVE_SHA="$GO_ARM64_SHA256" ;;','aarch64|arm64) GOARCH=arm64; EXPECTED_RC_SHA="$RC_ARM64_SHA256"; EXPECTED_PRIOR_RC_SHA="$PRIOR_RC_ARM64_SHA256"; GO_ARCHIVE_SHA="$GO_ARM64_SHA256" ;;',1)

needle='backup_original_trust() {\n'
func=r'''package_accepted_beta() {
  STEP="package-accepted-beta1"
  log "Package preserved accepted beta.1 for exact upgrade-path regression"
  local d bin="" v c built_at check="$BASE/beta-package-check"
  for d in /usr/local/lib/control-center/releases/*; do
    [[ -x "$d/control-center" ]] || continue
    v="$("$d/control-center" build-info --field version 2>/dev/null || true)"
    c="$("$d/control-center" build-info --field commit 2>/dev/null || true)"
    if [[ "$v" == "$BETA_VERSION" && "$c" == "$BETA_COMMIT" ]]; then
      bin="$d/control-center"
      break
    fi
  done
  [[ -n "$bin" ]] || die "accepted beta.1 release binary is not preserved on host"
  built_at="$("$bin" build-info --field built-at)"
  [[ "$built_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "accepted beta.1 built-at is not canonical RFC3339 UTC"
  (cd "$SOURCE_DIR" && go run ./cmd/release-tool package \
    --binary "$bin" --version "$BETA_VERSION" --commit "$BETA_COMMIT" --built-at "$built_at" --arch "$GOARCH" \
    --private-key "$PRIVATE_KEY" --output "$BETA_PACKAGE" >/dev/null)
  rm -rf "$check"; mkdir -p "$check"
  tar -xzf "$BETA_PACKAGE" -C "$check"
  "$SOURCE_DIR/dist/control-center-linux-$GOARCH" verify-release \
    --manifest "$check/manifest.json" --signature "$check/manifest.sig" --public-key "$PUBLIC_KEY" \
    --artifact "$check/control-center" --field release-id >/dev/null
  rm -rf "$check"
}

'''
if src.count(needle) != 1: raise SystemExit('ERROR: trust function anchor mismatch')
src=src.replace(needle,func+needle,1)

old='''  [[ "$(current_version)" == "$BETA_VERSION" ]] || die "host is not on accepted beta.1"\n  [[ "$(current_commit)" == "$BETA_COMMIT" ]] || die "host beta.1 commit is not the accepted source identity"\n  systemctl is-active --quiet nginx.service || die "test HTTP ingress nginx is not active"\n'''
new='''  [[ "$(current_version)" == "$RC_VERSION" ]] || die "host is not on the previously tested rc.1"\n  [[ "$(current_commit)" == "$PRIOR_RC_COMMIT" ]] || die "host prior rc.1 commit is not the expected source identity"\n  printf '%s  %s\\n' "$EXPECTED_PRIOR_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -\n  systemctl is-active --quiet nginx.service || die "test HTTP ingress nginx is not active"\n'''
if src.count(old) != 1: raise SystemExit('ERROR: phase initial preflight anchor mismatch')
src=src.replace(old,new,1)

old='''  build_exact_candidate\n  package_exact_candidate\n\n  STEP="upgrade-beta1-to-rc1"\n  log "Upgrade accepted beta.1 to exact rc.1"\n  install_test_trust\n  PRODUCT_CHANGED=1\n  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE"\n'''
new='''  build_exact_candidate\n  package_exact_candidate\n  package_accepted_beta\n\n  STEP="restore-accepted-beta1"\n  log "Restore accepted beta.1 before final rc.1 upgrade regression"\n  install_test_trust\n  PRODUCT_CHANGED=1\n  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$BETA_PACKAGE" --allow-downgrade\n  wait_ready "$BACKEND_URL" || die "accepted beta.1 did not become ready"\n  [[ "$(current_version)" == "$BETA_VERSION" && "$(current_commit)" == "$BETA_COMMIT" ]] || die "accepted beta.1 restore identity mismatch"\n\n  STEP="upgrade-beta1-to-final-rc1"\n  log "Upgrade accepted beta.1 to final exact rc.1"\n  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE"\n'''
if src.count(old) != 1: raise SystemExit('ERROR: upgrade block anchor mismatch')
src=src.replace(old,new,1)

src=src.replace('state changed during rc upgrade/security read-only acceptance','state changed during beta restore/final rc upgrade/security acceptance',1)
src=src.replace('secrets changed during rc upgrade/security read-only acceptance','secrets changed during beta restore/final rc upgrade/security acceptance',1)

report_anchor='''    echo "candidate_expected_sha256=$EXPECTED_RC_SHA"\n    echo "go_version=$GO_VERSION"\n'''
report_new='''    echo "candidate_expected_sha256=$EXPECTED_RC_SHA"\n    echo "prior_rc_commit=$PRIOR_RC_COMMIT"\n    echo "prior_rc_expected_sha256=$EXPECTED_PRIOR_RC_SHA"\n    echo "go_version=$GO_VERSION"\n'''
if src.count(report_anchor) != 1: raise SystemExit('ERROR: report anchor mismatch')
src=src.replace(report_anchor,report_new,1)

Path(sys.argv[2]).write_text(src)
PY

printf '%s  %s\n' "$V7_SCRIPT_SHA256" "$WORK/v7.sh" | sha256sum -c -
bash -n "$WORK/v7.sh"
chmod 0700 "$WORK/v7.sh"

if [[ ${RC1_V7_BUILD_ONLY:-0} == 1 ]]; then
  cp "$WORK/v7.sh" "${OUTPUT_V7:?OUTPUT_V7 required for build-only}"
  echo "V7_BUILD_ONLY=PASSED"
  exit 0
fi

exec bash "$WORK/v7.sh"
