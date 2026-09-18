#! /bin/sh
# Shared helper sourced by check-changelog, run-formatter, and
# clean-package-lock-registry (and by hooks/pre-commit itself). Not intended
# to be run directly. Depends on the caller already defining die().
#
# Implements the shared `[--all-files]` convention: a script that derives its
# own file list from git must select every tracked file (git ls-files)
# instead of only staged ones (git diff --cached) when running in all-files
# mode, or it silently reverts to a no-op there whenever nothing happens to
# be staged. See ai/local/scripts.instructions.md's "Purpose of --all-files
# mode" section for the full rationale.

# Sets MODE to "commit" (default) or "all-files" from $1, dying via the
# caller's die() on any other argument.
parse_all_files_mode_arg() {
    MODE=commit
    case "${1:-}" in
        "") ;;
        --all-files) MODE=all-files ;;
        *) die "unknown argument: $1 (supported: --all-files)" ;;
    esac
}

# Prints the files matching the extended grep pattern $1 from the current
# MODE's target set: every tracked file in all-files mode, staged
# non-deleted files only otherwise. Requires MODE to already be set (see
# parse_all_files_mode_arg above).
#
# --diff-filter=d (exclusion-based) rather than an inclusion list like ACM:
# an inclusion list silently drops any status letter someone forgot to
# enumerate -- that is exactly how a rename with edited content (status R,
# not M) was excluded and let rename+edit-only commits skip hooks/pre-commit's
# own checks (see its STAGED variable, fixed for the identical reason).
git_target_files() {
    if [ "$MODE" = "all-files" ]; then
        git ls-files | grep -E "$1"
    else
        git diff --cached --name-only --diff-filter=d | grep -E "$1"
    fi
}
