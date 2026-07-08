#!/usr/bin/env bash
# Shared helpers for the bats acceptance test suites.
#
# Each test gets an isolated temporary git repository in BATS_TEST_TMPDIR.
# The pre-commit hook is run as a subprocess; no hook code is sourced.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_DIR}/src/hooks"
HOOK="${HOOKS_DIR}/pre-commit"

# ── git config isolation ──────────────────────────────────────────────────────
# Without this, `git config <key>` inside a test repo falls through to the
# real developer's ~/.gitconfig (and any /etc/gitconfig) for any value the
# test repo hasn't set locally — e.g. `git config --unset user.email` in a
# test only removes the *local* value, so the check under test would still
# see the host machine's real global email. Pointing both scopes at /dev/null
# makes every test repo's git config fully hermetic; make_repo() and each
# test set everything the hook/scripts need at the local scope explicitly.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

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

# ── Shared test GPG identity ──────────────────────────────────────────────────
# check-identity requires a working GPG signing key, so every repo made by
# make_repo() needs one. Generated once per `bats` invocation (cached in
# BATS_RUN_TMPDIR, which is shared across all test files in the run) rather
# than once per test, since key generation — while fast — is unnecessary
# overhead to repeat per test.
TEST_GIT_EMAIL="test@example.com"
GNUPGHOME="${BATS_RUN_TMPDIR}/gnupg"
export GNUPGHOME
TEST_GIT_SIGNINGKEY=""

# Generates the shared test GPG key on first use; reuses it on subsequent calls
# (within this run and across files, via the GNUPGHOME/keyid cache above).
ensure_test_gpg_key() {
    local _keyid_file="${GNUPGHOME}/.keyid"
    if [ -f "${_keyid_file}" ]; then
        TEST_GIT_SIGNINGKEY="$(cat "${_keyid_file}")"
        return 0
    fi
    mkdir -p "${GNUPGHOME}"
    chmod 700 "${GNUPGHOME}"
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "${TEST_GIT_EMAIL}" ed25519 sign never > /dev/null 2>&1
    TEST_GIT_SIGNINGKEY="$(gpg --batch --list-secret-keys --with-colons "${TEST_GIT_EMAIL}" \
        | awk -F: '/^sec/{print $5; exit}')"
    printf '%s' "${TEST_GIT_SIGNINGKEY}" > "${_keyid_file}"
}

# Creates an isolated git repository in BATS_TEST_TMPDIR on the given branch
# (default: feature/acceptance-test) and prints its path. Configured with a
# valid identity and GPG signing key so check-identity passes by default —
# tests that exercise check-identity itself override individual settings.
make_repo() {
    local _branch="${1:-feature/acceptance-test}"
    local _t="${BATS_TEST_TMPDIR}/repo"
    ensure_test_gpg_key
    mkdir -p "${_t}"
    git -C "${_t}" init --quiet
    git -C "${_t}" symbolic-ref HEAD "refs/heads/${_branch}"
    git -C "${_t}" config user.email "${TEST_GIT_EMAIL}"
    git -C "${_t}" config user.name "Test User"
    git -C "${_t}" config commit.gpgsign true
    git -C "${_t}" config user.signingkey "${TEST_GIT_SIGNINGKEY}"
    git -C "${_t}" config core.hooksPath "${HOOKS_DIR}"
    printf '%s' "${_t}"
}

# Runs the hook in the given repo directory using TEST_PATH (dotnet stripped
# when not at the expected location).  Sets $status and $output via bats run.
# bats 1.10.x (Ubuntu 24.04) does not export bats_readlinkf from its wrapper
# when invoked from a sh parent process; without it bats-exec-file cannot locate
# bats-exec-test.  Defining and exporting bats_readlinkf here ensures the inner
# bats library always resolves its own path correctly (defence-in-depth alongside
# the same fix in src/scripts/run-bats).
# The four per-run tmpdir vars are also cleared so the inner bats starts with a
# fresh tmpdir hierarchy rather than re-using the outer suite directories.
run_hook() {
    local _repo="$1"
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" sh "$3"
    ' _ "${_repo}" "${TEST_PATH}" "${HOOK}"
}

# Runs the hook with a custom PATH and XDG_CACHE_HOME (for freshness tests).
# run_hook_env <repo> <path> <xdg_cache_home>
run_hook_env() {
    local _repo="$1"
    local _path="$2"
    local _cache="$3"
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" XDG_CACHE_HOME="$3" sh "$4"
    ' _ "${_repo}" "${_path}" "${_cache}" "${HOOK}"
}

# Runs the hook in the given repo directory with HOOKS_REPO_DIR_TEST_OVERRIDE set to the
# repo path so that the hook's protected-file guard fires as if this were the hooks repo.
run_hook_as_hooks_repo() {
    local _repo="$1"
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" HOOKS_REPO_DIR_TEST_OVERRIDE="$1" sh "$3"
    ' _ "${_repo}" "${TEST_PATH}" "${HOOK}"
}

# Returns true (0) when running inside any OCI container (Docker, Podman, etc.).
# Mirrors is_container() in src/hooks/pre-commit — keep in sync if either changes.
in_container() {
    [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "${container:-}" ] \
        || grep -q 'docker\|containerd\|kubepods' /proc/1/cgroup 2>/dev/null
}

# Runs the hook as an AI agent (CLAUDECODE=1) with a custom PATH and XDG_CACHE_HOME.
# run_hook_env_as_agent <repo> <path> <xdg_cache_home>
run_hook_env_as_agent() {
    local _repo="$1"
    local _path="$2"
    local _cache="$3"
    run bash -c '
        cd "$1"
        unset BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env CLAUDECODE=1 PATH="$2" XDG_CACHE_HOME="$3" sh "$4"
    ' _ "${_repo}" "${_path}" "${_cache}" "${HOOK}"
}
