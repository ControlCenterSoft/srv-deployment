# Perplexity external research

Perplexity is integrated into the `1.1.x` development line as an **advisory external-research layer**.
It is not a Control Center runtime dependency and it does not change product behavior when disabled.

## Role separation

- deterministic CI remains authoritative for build, tests, contracts and security checks;
- Gemini performs independent review of the local git diff;
- Perplexity verifies external facts that can become stale: upstream API behavior, deprecations,
  current compatibility guidance, release notes, security advisories and primary-source documentation.

This avoids using two AI providers for the same review task.

## GitHub Actions workflow

Workflow: `.github/workflows/perplexity-research.yml`

It runs for:

- pull requests targeting `1.1.x`;
- direct pushes to `1.1.x`;
- manual `workflow_dispatch`, optionally with a focused research question.

For pull requests the workflow maintains a single comment marked with
`<!-- control-center-perplexity-research -->`. Direct pushes and manual runs publish their report
to the GitHub Actions step summary.

The workflow runs `scripts/secret-scan.sh` before any external API call. If that scan fails, no diff
is sent to Perplexity.

## Required repository secret

Create the Actions repository secret:

```text
PERPLEXITY_API_KEY
```

The key must never be committed to the repository, written to `deployment.json`, passed to the
Control Center runtime, or stored in documentation.

Optional repository variable:

```text
PERPLEXITY_MODEL=sonar-pro
```

`sonar-pro` is the default. The model can be changed through the repository variable without a code
change.

## API contract

`scripts/perplexity_research.py` uses the canonical Sonar endpoint:

```text
POST https://api.perplexity.ai/v1/sonar
Authorization: Bearer <PERPLEXITY_API_KEY>
Content-Type: application/json
```

Only the bounded git diff plus repository/change metadata and an optional manual focus are sent.
The script stores no credentials and emits only the research response, source metadata and API usage
metadata into the current Actions job.

## Failure model

Perplexity is intentionally **advisory**:

- missing API key => research is skipped;
- API/network failure => report is marked unavailable;
- deterministic development gate continues independently;
- recommendations must be validated against project contracts, tests and primary documentation.

The local parser/prompt regression tests are mandatory CI so the integration itself cannot silently
drift even though the external service is optional.
