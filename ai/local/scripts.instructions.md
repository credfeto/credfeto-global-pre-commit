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

## Purpose of `--all-files` mode (MANDATORY)

`hooks/pre-commit --all-files` (invoked via the `pre-commit-check` wrapper) exists to detect, and wherever a fixer script exists for the problem silently *fix*, every issue across the whole tracked tree, with no commit in progress. It is the supported way to get a trustworthy "everything in the repo is clean" signal, e.g. as the mandatory pre-work baseline check before starting a task (see `ai/global/git.instructions.md`'s "Pre-Work Baseline Check"). A false "all checks passed" result from `--all-files` defeats that purpose for every consumer of this repo's hooks, so this is treated as a correctness bug, not a nice-to-have, whenever it happens.

**Corollary for script authors (MANDATORY):** any script that derives its own file list from git state (`git diff --cached`, `git status`, etc.) instead of taking it from the caller must recognise `--all-files` mode (accept it as `$1`, or otherwise have it threaded through) and switch to `git ls-files`, filtered the same way as its staged-mode list, when it is set. A script that unconditionally re-derives `git diff --cached` internally will silently no-op in `--all-files` mode whenever nothing happens to be staged, even though `hooks/pre-commit` itself correctly decided the category should run. This is not a hypothetical: `check-changelog`, `run-formatter`, and `clean-package-lock-registry` all shipped with exactly this bug, since none of them looked at the mode `hooks/pre-commit` had already resolved into `CHECK_FILES`, so all three silently skipped their real work under `--all-files` with an empty stage. See `hooks/pre-commit`'s `MODE_ARG` for the pattern that threads the mode down to a called script.

## Fixer scripts: staging and exit-code convention (MANDATORY)

A "fixer" script can modify files to correct a problem (e.g. `run-formatter`, `clean-package-lock-registry`) — distinct from a pure validator that only reports problems and never writes (e.g. `run-eslint`, `run-stylelint`, `run-psscriptanalyzer`, none of which pass `--fix`-style flags today).

Every fixer script must:

1. **Re-stage any file it modifies**, with `git add <file>`, before returning — the fix must land in the commit currently being built, not be left as an unstaged working-tree change.
2. **Exit 0 whenever the fix step itself succeeded**, regardless of whether any file was actually changed. Do not invent a distinct "success, and I changed something" exit code — there is no standard non-zero code reserved for this, and none should be added.
3. **Exit non-zero only on genuine failure** (the fixing tool itself errored, or a required dependency is missing). On this path, do not stage anything.

A caller that needs to know whether a fixer changed anything (for example, to tell a human/agent "some files were auto-fixed — re-add and re-run") must determine this itself by comparing repo state before and after the fixer ran (`git status --short` / `git diff --cached --name-only`), not by inspecting the fixer's exit code.

`run-formatter` and `clean-package-lock-registry` are the reference implementations of this convention.
