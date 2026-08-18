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

# Runs "$@" once per bats run, guarded by flock on <marker>.lock so concurrent
# bats --jobs processes racing the check-then-create sequence against shared
# state (a GPG key, a downloaded trivy DB) serialise instead of corrupting it.
# The marker is only created once "$@" succeeds. The plain existence check up
# front is a fast path for the (overwhelmingly common) already-cached case,
# avoiding flock/subshell overhead once the marker exists. Always locks under
# fd 200: each call runs in its own subshell, so the fd number isn't shared
# state.
# _run_once <marker_file> <command...>
_run_once() {
    local _marker="$1"
    shift
    [ -f "${_marker}" ] && return 0
    (
        flock -x 200
        if [ ! -f "${_marker}" ]; then
            "$@" && touch "${_marker}"
        fi
    ) 200> "${_marker}.lock"
}

# Generates a test GPG key. The marker file doubles as the keyid cache.
_generate_gpg_keyid() {
    local _email="$1"
    local _keyid_file="$2"
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "${_email}" ed25519 sign never > /dev/null 2>&1
    gpg --batch --list-secret-keys --with-colons "${_email}" \
        | awk -F: '/^sec/{print $5; exit}' > "${_keyid_file}"
}

# Generates a test GPG key on first use; reuses it on subsequent calls (within
# this run and across files, via the GNUPGHOME/keyid cache above). mkdir/chmod
# are cheap and idempotent, so they run unconditionally; _run_once's own fast
# path skips the flock/generate work once the key has been generated.
_ensure_gpg_key() {
    local _email="$1"
    local _keyid_file="$2"
    mkdir -p "${GNUPGHOME}"
    chmod 700 "${GNUPGHOME}"
    _run_once "${_keyid_file}" _generate_gpg_keyid "${_email}" "${_keyid_file}"
    IFS= read -r _keyid < "${_keyid_file}"
    printf '%s' "${_keyid}"
}

ensure_test_gpg_key() {
    TEST_GIT_SIGNINGKEY="$(_ensure_gpg_key "${TEST_GIT_EMAIL}" "${GNUPGHOME}/.keyid")"
}

# Pre-warms trivy's vulnerability DB once per bats run, via the same _run_once
# guard as _ensure_gpg_key above. trivy's own metadata.json write has no
# cross-process lock, so two of linters.bats's trivy tests updating the DB at
# the same moment under bats --jobs raced and corrupted the loser's read
# (json decode error: EOF). Warming the shared cache once before either test's
# own trivy invocation means both see an already-fresh DB and never write.
_TRIVY_DB_WARM_MARKER="${BATS_RUN_TMPDIR}/.trivy-db-warm"
ensure_trivy_db_warm() {
    command -v trivy > /dev/null 2>&1 || return 0
    _run_once "${_TRIVY_DB_WARM_MARKER}" trivy fs --download-db-only --quiet "${BATS_RUN_TMPDIR}"
}

# Second, distinct test GPG identity (different email), used only by
# identity.bats's signingkey-email-mismatch test. Cached the same way as
# ensure_test_gpg_key() above, via the shared _ensure_gpg_key() helper.
OTHER_TEST_GIT_EMAIL="other@example.com"
OTHER_TEST_GIT_SIGNINGKEY=""

ensure_other_test_gpg_key() {
    # shellcheck disable=SC2034 # read by test/identity.bats via `load test_helper`
    OTHER_TEST_GIT_SIGNINGKEY="$(_ensure_gpg_key "${OTHER_TEST_GIT_EMAIL}" "${GNUPGHOME}/.other-keyid")"
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
# HOOKS_REPO_DIR_TEST_OVERRIDE, if exported by the caller (see freshness.bats),
# is inherited by bash -c like any other exported variable.
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

# Runs the hook with IS_AMEND_TEST_OVERRIDE=1, simulating the invoking git
# commit having been run with --amend (see is_amend in src/hooks/pre-commit —
# the real signal is the parent process's own command line, which this
# bash -c/sh invocation can never make look like `git commit --amend`).
run_hook_as_amend() {
    local _repo="$1"
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" IS_AMEND_TEST_OVERRIDE=1 sh "$3"
    ' _ "${_repo}" "${TEST_PATH}" "${HOOK}"
}

# Runs the hook in --all-files (baseline) mode using TEST_PATH.
# Sets $status and $output via bats run.
run_hook_all_files() {
    local _repo="$1"
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" sh "$3" --all-files
    ' _ "${_repo}" "${TEST_PATH}" "${HOOK}"
}

# Runs the hook with a custom PATH and XDG_CACHE_HOME (for freshness tests).
# HOOKS_REPO_DIR_TEST_OVERRIDE, if exported by the caller (see freshness.bats),
# is inherited by bash -c like any other exported variable.
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
# HOOKS_REPO_DIR_TEST_OVERRIDE, if exported by the caller (see freshness.bats),
# is inherited by bash -c like any other exported variable.
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
