#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail() { printf 'SECRET SCAN FAILED: %s\n' "$*" >&2; exit 1; }

# Secret-bearing file names must never be committed as product source/artifacts.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  fail "secret-bearing file present: $path"
done < <(find . -type f \
  \( -name '*.p12' -o -name '*.pfx' -o -name '*.key' -o -name '*.secret' -o -name '*credentials*' \) \
  -not -path './.git/*' -print)

# Actual private-key material, not code strings that merely discuss passwords.
if grep -RIl --exclude-dir=.git -E -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' . | grep -q .; then
  grep -RIl --exclude-dir=.git -E -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' . >&2 || true
  fail 'private key material found'
fi

# Common live-token prefixes. Placeholder/test words without these prefixes are allowed.
if grep -RIl --exclude-dir=.git -E '(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16})([^A-Za-z0-9]|$)' . | grep -q .; then
  grep -RIl --exclude-dir=.git -E '(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16})([^A-Za-z0-9]|$)' . >&2 || true
  fail 'credential-like token found'
fi

printf 'Secret scan passed: no private-key material, secret-bearing files or live-token prefixes found.\n'
