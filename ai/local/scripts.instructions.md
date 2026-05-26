<!-- Locally Maintained -->
# Script Management Rules

[← Local index](index.md)

This file covers the rules for adding and removing scripts in this repository.

## When adding a new script

1. Create the script in the `src/scripts/` directory.
2. Add `"$SCRIPTS_DIR/<script-name>" \` to the `chmod +x` block in `install`.
3. If the hook calls it, verify it's referenced correctly in `src/hooks/pre-commit` or `src/hooks/pre-push`.

## When removing or inlining a script

1. Delete (or inline) the script file from `src/scripts/`.
2. Remove the corresponding `"$SCRIPTS_DIR/<script-name>" \` line from the `chmod +x` block in `install`.
3. Remove or update any calls to it in `src/hooks/pre-commit` or `src/hooks/pre-push`.

## Invariant to maintain

The `chmod +x` list in `install` must exactly match the set of files that:

- Exist in `src/scripts/`, **and**
- Are executable entry points (called by a hook or directly by a user).

Root-level executables (e.g. `acceptance-test`) use `$REPO_DIR/<name>` in the chmod block rather than `$SCRIPTS_DIR/<name>` — they do not go in `src/scripts/`.

Before committing any change that adds, removes, or renames a script, verify the `chmod +x` list is consistent with the actual contents of `src/scripts/`.
