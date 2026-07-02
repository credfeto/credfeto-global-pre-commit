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

## `language: system` wrappers must be exposed on PATH (MANDATORY)

Wrapper scripts referenced by a `language: system` hook in `src/.pre-commit-config.yaml` **by bare command name** (e.g. `entry: run-eslint`) are resolved by pre-commit through `PATH` — **not** through `$SCRIPTS_DIR`. The hook (`src/hooks/pre-commit`) calls its own scripts by full `$SCRIPTS_DIR/<name>` path, but it does **not** add `$SCRIPTS_DIR` to `PATH`, so a bare-name wrapper resolves only if its directory is already on `PATH`.

`install` bridges this in the `# ── Symlink system-hook wrappers onto PATH` block, which symlinks each such wrapper into `$HOME/.local/bin`.

When adding a new `language: system` wrapper that is invoked by bare name (currently `run-eslint`, `run-stylelint`, `run-psscriptanalyzer`, `run-bats`):

1. Add it to the `chmod +x` block in `install` (see *When adding a new script*).
2. **Also** add a symlink line for it to the *Symlink system-hook wrappers onto PATH* block in `install`.
3. Consuming container images (e.g. `credfeto-orchestrator`'s `development-full` / `development-agent`) put `src/scripts/` on `PATH` and verify each wrapper resolves **at build time** — a wrapper added here is not reachable in those images until their build-time check list is updated. Those images are designed to fail the build rather than surface a missing wrapper as an `Executable <name> not found` hook failure at commit time.

Wrappers invoked only through the hook by full `$SCRIPTS_DIR/<name>` path (e.g. `run-formatter`, `buildcheck`) do **not** need a PATH symlink.
