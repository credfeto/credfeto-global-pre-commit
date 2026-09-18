#!/usr/bin/env bats
# Enforces the MANDATORY "Corollary for script authors" in
# ai/local/scripts.instructions.md's "Purpose of --all-files mode" section:
# any script under src/scripts/ that derives its own file list from git
# state must go through src/scripts/lib/mode-arg.sh's git_target_files(),
# not call `git diff --cached` or `git status` directly, or it silently
# reverts to a no-op under --all-files mode whenever nothing is staged
# (the exact bug fixed by issue #232).
#
# Scoped to src/scripts/ only, and enforced here as a bats test rather than
# a src/.pre-commit-config.yaml hook: that config also serves as the global
# fallback config for any consumer repo lacking its own (see
# hooks/pre-commit's `pre-commit run --config "$REPO_DIR/.pre-commit-config.yaml"`),
# so a hook entry targeting src/scripts/* there would incorrectly fire
# against any unrelated repo that happens to have a directory of that name.
#
# This is a static grep, not a shell parser: it cannot see a call routed
# through a variable/wrapper/alias, and it only recognises a whole-line
# comment (not a trailing inline one) as non-executable. Both are accepted,
# known limitations of a lightweight text-based guard, not something this
# test tries to fully solve.

load test_helper

@test "no script under src/scripts (other than lib/mode-arg.sh) calls git diff --cached or git status directly" {
    local _hits
    # `|| true` neutralises grep's own exit status: the final grep -v
    # legitimately exits 1 (its POSIX "no output" convention) whenever
    # every candidate line is a comment, i.e. exactly the success case the
    # `[ -z ]` check below needs to see, not an error.
    _hits=$( { grep -rnE 'git[[:space:]]+(diff[[:space:]]+--cached|status)' "${REPO_DIR}/src/scripts" \
        | grep -v '/lib/mode-arg\.sh:' \
        | grep -vE ':[0-9]+:[[:space:]]*#'; } || true)
    [ -z "${_hits}" ]
}
