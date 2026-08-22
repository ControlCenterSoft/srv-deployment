# P0 Contract & Regression QA evidence — PR #222

Parent exact head: `651589e147ca441e19f7e57436f93b5f139b3086`.

## Release-blocking regression

The current head reintroduces the merge-authority defect previously fixed by QA child PR #223 (`719c9220c324bcafac5f0237b052d8ab69672ac0`). The trusted `pull_request_target` release gate is no longer a read-only validator:

- `.github/workflows/release-gate.yml` grants the workflow token `contents: write`;
- the workflow mints a dedicated GitHub App token able to submit an `APPROVE` review;
- the workflow invokes `scripts/release_gate.py` without `--no-merge`;
- `scripts/release_gate.py` submits the machine approval and then calls the GitHub merge API;
- `tests/test_release_gate_policy.py` was changed to require this write/auto-merge behavior, so the green branch CI no longer protects the PRE-GATE -> GATE-READY -> GATE-FROZEN operating model.

This contradicts the PR description, which still states that the fixed independent reviewer is `controlcenter-release-reviewer`, the trusted workflow is read-only, and the Integrator remains the only merge authority.

## Deterministic reproduction

Run from the exact parent head:

```bash
git checkout 651589e147ca441e19f7e57436f93b5f139b3086

grep -nE 'contents:|pull-requests:|create-github-app-token|RELEASE_GATE_APP_PRIVATE_KEY|--no-merge' .github/workflows/release-gate.yml
grep -nE 'RELEASE_GATE_REVIEWER|submit_app_approval|/merge|AUTOMATED_MERGE_COMPLETED' scripts/release_gate.py

python3 - <<'PY'
from pathlib import Path
w = Path('.github/workflows/release-gate.yml').read_text()
s = Path('scripts/release_gate.py').read_text()
assert 'contents: read' in w, 'P0: trusted gate is not read-only'
assert 'contents: write' not in w, 'P0: trusted gate has repository write authority'
assert '--no-merge' in w, 'P0: trusted gate can execute merge path'
assert 'controlcenter-release-reviewer' in s, 'P0: fixed independent human reviewer boundary removed'
assert 'control-center-release-gate[bot]' not in s, 'P0: machine reviewer replaced independent reviewer boundary'
PY
```

Expected result on the current head: the assertions fail because write authority, machine approval, and the merge path are present.

## QA gate consequence

`651589e147ca441e19f7e57436f93b5f139b3086` is **P0 BLOCK / not GATE-READY**. All Contract/Security PASS evidence anchored to earlier `719c9220...` is stale because executable workflow/policy/test code changed.

Required remediation is product/governance semantics and therefore is intentionally not implemented by Contract & Regression QA. Restore the read-only/no-merge Integrator boundary (equivalent to the invariant previously enforced by #223), integrate the fix through the owner/Integrator, and obtain fresh exact-head Contract QA + Security evidence on the resulting SHA before any GATE-FROZEN/merge decision.
