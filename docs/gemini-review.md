# Gemini Independent Review

Control Center uses Gemini as a second, independent code reviewer. Gemini is not a deployment agent and does not receive write access to repository contents or the test server.

## GitHub configuration

Required repository secret:

- `GEMINI_API_KEY` — Gemini API authorization key created in Google AI Studio.

Optional repository variables:

- `GEMINI_MODEL` — model name. Default: `gemini-3.6-flash`.
- `GEMINI_GATE_LEVEL` — minimum severity that fails the review check. Default: `HIGH`. Accepted values: `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, `NONE`.

Do not commit the API key to the repository, deployment manifest, server configuration, workflow YAML, issue, or pull request.

## Review behavior

The workflow runs for non-draft pull requests, pushes to `main` excluding `ops/**`, and manual workflow dispatches after the workflow is present on the default branch.

For pull requests it:

1. Builds a git diff between the PR base and head commits.
2. Sends the diff to the Gemini API over HTTPS.
3. Treats the complete diff as untrusted data and explicitly rejects instructions embedded in source code, comments, strings, filenames, or documentation.
4. Requests a structured review with `BLOCKER`, `HIGH`, `MEDIUM`, and `LOW` severities.
5. Updates one persistent PR comment rather than creating a new comment on every synchronization.
6. Fails the check when a finding meets or exceeds `GEMINI_GATE_LEVEL`.

For pushes to `main`, the same result is written to the GitHub Actions job summary and the severity gate is enforced.

## Security boundaries

- Gemini receives the review diff, repository name, change identifier, and head commit SHA.
- The API key is provided only through the GitHub Actions secret store.
- The Gemini workflow has `contents: read` and `pull-requests: write` permissions. It cannot push commits or deploy releases.
- Pull requests from forks do not receive repository secrets and therefore cannot invoke Gemini with the repository API key.
- Gemini output is treated as review evidence only. It is never executed as shell, Python, deployment metadata, or configuration.
- The submitted diff is capped before transmission to bound request size and cost.

## Local tests

Run:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile scripts/gemini_review.py
```
