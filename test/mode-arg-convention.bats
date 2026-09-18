#!/usr/bin/env bats
# Enforces the MANDATORY "Corollary for script authors" in
# ai/local/scripts.instructions.md's "Purpose of --all-files mode" section:
# any script under src/scripts/ that derives its own file list from git
# state must go through src/scripts/lib/mode-arg.sh's git_target_files(),
# not call `git diff --cached`/`--staged` or `git status` directly, or it
# silently reverts to a no-op under --all-files mode whenever nothing is
# staged (the exact bug fixed by issue #232).
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

@test "no script under src/scripts (other than lib/mode-arg.sh) calls git diff --cached/--staged or git status directly" {
    [ -d "${REPO_DIR}/src/scripts" ] || fail "src/scripts directory not found under REPO_DIR"

    local _hits
    # A single awk pass: matches a candidate line, excludes lib/mode-arg.sh
    # by its path field only (not a substring anywhere in the line), and
    # excludes only a whole-line comment (leading '#', ignoring indentation)
    # -- never a mid-line grep -v stage, whose "no output" exit status (1)
    # would otherwise be indistinguishable from a genuine zero-violations
    # pass. awk always exits 0 when it runs to completion, whether or not
    # it printed anything, so no `|| true` is needed here.
    _hits=$(grep -rnE 'git[[:space:]]+.*(diff[[:space:]]+.*--(cached|staged)|status)' "${REPO_DIR}/src/scripts" \
        | awk -F: '
            $1 ~ /\/lib\/mode-arg\.sh$/ { next }
            # benchmark-test-affected deliberately does not take --all-files:
            # it fails open on an empty stage (runs every benchmark, the
            # opposite failure mode of the bug fixed in issue #232), an
            # intentional, reviewed exception rather than an instance of it.
            $1 ~ /\/benchmark-test-affected$/ { next }
            {
                content = $0
                sub(/^[^:]*:[0-9]+:/, "", content)
                sub(/^[ \t]+/, "", content)
                if (content !~ /^#/) print
            }
        ')
    if [ -n "${_hits}" ]; then
        printf 'Found direct git status/diff --cached usage outside lib/mode-arg.sh:\n%s\n' "${_hits}" >&2
        return 1
    fi
}
