<!-- Locally Maintained -->
# Linter Rules

[← Local index](index.md)

This file covers rules for adding, removing, and modifying linters in this repository.

## When adding or changing a linter

Whenever a linter is added, removed, or reconfigured in `.pre-commit-config.yaml`:

1. Add or update a test in `acceptance-test` that covers the linter.
2. Every linter must have **at least two tests**:
   - One that stages an **invalid** file and expects the hook to exit non-zero.
   - One that stages a **valid** file and expects the hook to exit zero.
3. Each test must use a project-level `.pre-commit-config.yaml` scoped to that linter alone — do not rely on the global config, as other linters could mask the result.
4. If the linter tool may not be installed on all machines, guard the test with a `command -v <tool>` check and emit a `SKIP` message (using `info`) rather than failing.

## When removing a linter

Remove the corresponding test(s) from `acceptance-test` so the test count stays accurate.

## Before every commit (MANDATORY)

Run `./acceptance-test` from the repo root and confirm all tests pass before staging or committing any change to this repository. Do not commit if any test fails.
