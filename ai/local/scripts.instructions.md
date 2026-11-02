<!-- Locally Maintained -->
# Script Management Rules

[← Local index](index.md)

This file covers the rules for adding and removing scripts in this repository.

## When adding a new script

1. Create the script in the `src/scripts/` directory.
2. Add `"$SCRIPTS_DIR/<script-name>" \` to the file list of the `make_executable` call in `install`.
3. If the hook calls it, verify it's referenced correctly in `src/hooks/pre-commit` or `src/hooks/pre-push`.

## When removing or inlining a script

1. Delete (or inline) the script file from `src/scripts/`.
2. Remove the corresponding `"$SCRIPTS_DIR/<script-name>" \` line from the file list of the `make_executable` call in `install`.
3. Remove or update any calls to it in `src/hooks/pre-commit` or `src/hooks/pre-push`.

## Invariant to maintain

The file list of the `make_executable` call in `install` must contain exactly these files, and nothing else:

- Every executable entry point in `src/scripts/` (a script called by a hook or directly by a user), listed as `$SCRIPTS_DIR/<name>`.
- Every hook in `src/hooks/` (`pre-commit` and `pre-push`), listed as `$HOOKS_DIR/<name>`.
- Every root-level executable other than `install` itself (e.g. `check-setup`, `acceptance-test`), listed as `$REPO_DIR/<name>`. `install` is left out because it is the script that applies the list.

`install` is the only step that guarantees these files carry the executable bit, so a file missing from the list fails to run wherever that bit was lost, and a file in the list that is not an entry point (such as a sourced library under `src/scripts/lib/`) is made executable for no reason.

Before committing any change that adds, removes, or renames a script, hook or root-level executable, verify the `make_executable` file list is consistent with the actual contents of `src/scripts/`, `src/hooks/` and the repository root.

## `language: system` wrappers invoked by bare name need no PATH symlink

Wrapper scripts referenced by a `language: system` hook in `src/.pre-commit-config.yaml` by bare command name (e.g. `entry: run-eslint`) are resolved by pre-commit through `PATH`. `src/hooks/pre-commit` prepends `$SCRIPTS_DIR` to `PATH` and exports it before anything else runs, and every supported run (a commit, and `pre-commit-check`, which calls the hook with `--all-files`) goes through that hook. Every bare-name wrapper therefore resolves to the copy shipped alongside the hook without any symlink.

When adding a new `language: system` wrapper that is invoked by bare name (MANDATORY):

1. Add it to the file list of the `make_executable` call in `install` (see *When adding a new script*), because pre-commit can only run it if it is executable.
2. Do not add a symlink line for it to `install`, because the hook already puts it on `PATH`.
3. Optionally add it to the consuming container images' (e.g. `credfeto-orchestrator`'s `development-full` / `development-agent`) build-time wrapper check. That check only confirms that the wrappers it names resolve; a wrapper it does not name is still reachable through `src/scripts/` on `PATH` and does not fail the image build.

A per-user install links the `run-*` wrappers already listed in the *Symlink system-hook wrappers onto PATH* block of `install` into `$HOME/.local/bin`; the hook does not need these links, which is why a new wrapper gets none (step 2 above). A `--system` install must create no wrapper links, because `src/hooks/pre-commit` prepends its own `src/scripts` to `PATH` for every user who commits through it.

`composite-action-lint` is not shipped in `src/scripts/`, so the hook cannot put it on `PATH`. A per-user install symlinks it from the Go bin directory into `$HOME/.local/bin`; a `--system` install must copy it (with `sudo install -m 0755`) into the system bin directory (`/usr/local/bin` by default) rather than symlink it, because a link into the installing user's home directory is unreadable for every other user.

## Purpose of `--all-files` mode (MANDATORY)

`hooks/pre-commit --all-files` (invoked via the `pre-commit-check` wrapper) exists to detect, and wherever a fixer script exists for the problem silently *fix*, every issue across the whole tracked tree, with no commit in progress. It is the supported way to get a trustworthy "everything in the repo is clean" signal, e.g. as the mandatory pre-work baseline check before starting a task (see `ai/global/git.instructions.md`'s "Pre-Work Baseline Check"). A false "all checks passed" result from `--all-files` defeats that purpose for every consumer of this repo's hooks, so this is treated as a correctness bug, not a nice-to-have, whenever it happens.

**Corollary for script authors (MANDATORY):** any script that derives its own file list from git state (`git diff --cached`, `git status`, etc.) instead of taking it from the caller must recognise `--all-files` mode (accept it as `$1`, or otherwise have it threaded through) and switch to `git ls-files`, filtered the same way as its staged-mode list, when it is set. A script that unconditionally re-derives `git diff --cached` internally will silently no-op in `--all-files` mode whenever nothing happens to be staged, even though `hooks/pre-commit` itself correctly decided the category should run. This is not a hypothetical: `check-changelog`, `run-formatter`, and `clean-package-lock-registry` all shipped with exactly this bug, since none of them looked at the mode `hooks/pre-commit` had already resolved into `CHECK_FILES`, so all three silently skipped their real work under `--all-files` with an empty stage. See `hooks/pre-commit`'s `MODE_ARG` for the pattern that threads the mode down to a called script. Enforced by `test/mode-arg-convention.bats`, which fails if any script under `src/scripts/` (other than `lib/mode-arg.sh` itself) calls `git diff --cached` or `git status` directly.

## Fixer scripts: staging and exit-code convention (MANDATORY)

A "fixer" script can modify files to correct a problem (e.g. `run-formatter`, `clean-package-lock-registry`) — distinct from a pure validator that only reports problems and never writes (e.g. `run-eslint`, `run-stylelint`, `run-psscriptanalyzer`, none of which pass `--fix`-style flags today).

Every fixer script must:

1. **Re-stage any file it modifies**, with `git add <file>`, before returning — the fix must land in the commit currently being built, not be left as an unstaged working-tree change.
2. **Exit 0 whenever the fix step itself succeeded**, regardless of whether any file was actually changed. Do not invent a distinct "success, and I changed something" exit code — there is no standard non-zero code reserved for this, and none should be added.
3. **Exit non-zero only on genuine failure** (the fixing tool itself errored, or a required dependency is missing). On this path, do not stage anything.

A caller that needs to know whether a fixer changed anything (for example, to tell a human/agent "some files were auto-fixed — re-add and re-run") must determine this itself by comparing repo state before and after the fixer ran (`git status --short` / `git diff --cached --name-only`), not by inspecting the fixer's exit code.

`run-formatter` and `clean-package-lock-registry` are the reference implementations of this convention.
