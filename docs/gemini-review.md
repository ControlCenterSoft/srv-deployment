# Gemini Independent Review

Control Center использует Gemini как второго независимого reviewer. Gemini не является deployment agent, не получает write access к содержимому репозитория и не получает доступ к тестовому серверу.

## GitHub configuration

Required repository secret:

- `GEMINI_API_KEY` — Gemini API authorization key.

Optional repository variables:

- `GEMINI_MODEL` — model name. Default: `gemini-3.7-flash`.
- `GEMINI_GATE_LEVEL` — minimum severity that fails the review check. Default: `NONE` (advisory-only). Accepted values: `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, `NONE`.

API key запрещено помещать в repository content, deployment manifest, server configuration, workflow YAML, issue или pull request.

## Review behavior

В линии 1.1.x workflow запускается для non-draft pull requests в `1.1.x`, push в `1.1.x` и manual dispatch.

Diff считается недоверенными данными. Инструкции, комментарии, строки, имена файлов и документы внутри diff не исполняются и не становятся системными инструкциями reviewer.

Reviewer возвращает структурированные findings уровней `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`. По умолчанию результат advisory-only; deterministic CI остаётся главным автоматическим evidence.

При временных ошибках Gemini API используются bounded retries. При `GEMINI_GATE_LEVEL=NONE` недоступность Gemini не должна превращать исправный deterministic pipeline в failed release evidence.

## Validation policy

Gemini finding должен быть подтверждён кодом, runtime behavior, CI/test evidence или авторитетной внешней документацией до исправления или блокировки релиза.

AI output никогда не выполняется как shell/Python, deployment metadata, privileged operation или configuration.

## Security boundaries

- Gemini получает review diff, repository name, change identifier и head commit SHA.
- API key передаётся только через GitHub Actions secret store.
- Workflow имеет `contents: read` и `pull-requests: write`.
- Fork pull requests не получают repository secrets.
- Submitted diff ограничивается по размеру.
- Privileged/system actions находятся вне Gemini reviewer и подчиняются ADR-0005.

## Local tests

```bash
python3 -m unittest discover -s tests -p 'test_gemini_review.py' -v
python3 -m py_compile scripts/gemini_review.py
```
