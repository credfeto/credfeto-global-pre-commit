#!/usr/bin/env bash
# Shared helpers for the bats acceptance test suites.
#
# Each test gets an isolated temporary git repository in BATS_TEST_TMPDIR.
# The pre-commit hook is run as a subprocess; no hook code is sourced.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_DIR}/src/hooks"
HOOK="${HOOKS_DIR}/pre-commit"

# ── PATH sanitisation ─────────────────────────────────────────────────────────
# The hook enforces that dotnet (if present) must resolve to
# /usr/share/dotnet/dotnet.  On machines where dotnet lives elsewhere we strip
# it from TEST_PATH so those tests are not aborted by the environment check.
# Tests that specifically exercise the dotnet-path validation supply their own
# controlled PATH and do not use TEST_PATH.
_EXPECTED_DOTNET="/usr/share/dotnet/dotnet"
_ACTUAL_DOTNET_BIN="$(command -v dotnet 2>/dev/null || true)"
_ACTUAL_DOTNET_REAL="$(readlink -f "${_ACTUAL_DOTNET_BIN}" 2>/dev/null || echo "${_ACTUAL_DOTNET_BIN}")"
if [ -n "${_ACTUAL_DOTNET_BIN}" ] && [ "${_ACTUAL_DOTNET_REAL}" != "${_EXPECTED_DOTNET}" ]; then
    _DOTNET_DIR="$(dirname "${_ACTUAL_DOTNET_BIN}")"
    TEST_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -Fxv "${_DOTNET_DIR}" | tr '\n' ':' | sed 's/:$//')"
else
    TEST_PATH="${PATH}"
fi
export TEST_PATH
export _ACTUAL_DOTNET_BIN
export _ACTUAL_DOTNET_REAL
export _EXPECTED_DOTNET

# Creates an isolated git repository in BATS_TEST_TMPDIR on the given branch
# (default: feature/acceptance-test) and prints its path.
make_repo() {
    local _branch="${1:-feature/acceptance-test}"
    local _t="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${_t}"
    git -C "${_t}" init --quiet
    git -C "${_t}" symbolic-ref HEAD "refs/heads/${_branch}"
    git -C "${_t}" config user.email "test@example.com"
    git -C "${_t}" config user.name "Test User"
    git -C "${_t}" config core.hooksPath "${HOOKS_DIR}"
    printf '%s' "${_t}"
}

# Runs the hook in the given repo directory using TEST_PATH (dotnet stripped
# when not at the expected location).  Sets $status and $output via bats run.
# bats 1.10.x does not reset per-run tmpdir variables at startup; all four are
# unset here so that any nested bats invocation (e.g. run-bats) starts with a
# completely fresh tmpdir hierarchy rather than re-using the outer suite dirs.
run_hook() {
    local _repo="$1"
    run bash -c 'cd "$1" && unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR && env PATH="$2" sh "$3"' _ "${_repo}" "${TEST_PATH}" "${HOOK}"
}

# Runs the hook with a custom PATH and XDG_CACHE_HOME (for freshness tests).
# run_hook_env <repo> <path> <xdg_cache_home>
run_hook_env() {
    local _repo="$1"
    local _path="$2"
    local _cache="$3"
    run bash -c 'cd "$1" && unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR && env PATH="$2" XDG_CACHE_HOME="$3" sh "$4"' _ "${_repo}" "${_path}" "${_cache}" "${HOOK}"
}
