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

# ── pre-commit store isolation ────────────────────────────────────────────────
# pre-commit records every config it runs in a SQLite database in its store
# (default ~/.cache/pre-commit/db.db). Under bats --jobs, concurrent tests all
# writing to that one shared database can hit "database is locked", which
# crashes pre-commit (exit 3) and fails whichever test was running it, and
# every test run also pollutes the developer's real pre-commit cache. Giving
# each test its own store removes both problems at no cost, since every hook
# the tests run is repo: local with language: system, so there is nothing to
# clone or build into it. The guard leaves PRE_COMMIT_HOME alone outside a
# test body (setup_file and bats' own preprocessing pass), where
# BATS_TEST_TMPDIR is not yet set and pre-commit is never run.
if [ -n "${BATS_TEST_TMPDIR:-}" ]; then
    export PRE_COMMIT_HOME="${BATS_TEST_TMPDIR}/pre-commit-home"
fi

# ── PATH sanitisation ─────────────────────────────────────────────────────────
# The hook enforces that dotnet (if present) must resolve to
# /usr/share/dotnet/dotnet.  On machines where dotnet lives elsewhere we strip
# it from TEST_PATH so those tests are not aborted by the environment check.
# Tests that specifically exercise the dotnet-path validation supply their own
# controlled PATH and do not use TEST_PATH.
# The expected path is canonicalised exactly as the hook does, so a symlinked
# /usr/share/dotnet (e.g. -> dotnet-<timestamp>) counts as the correct location.
_EXPECTED_DOTNET="$(readlink -f /usr/share/dotnet/dotnet 2>/dev/null || echo /usr/share/dotnet/dotnet)"
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
# avoiding flock/subshell overhead once the marker exists. mkdir -p on the
# marker's directory only runs on that same slow path, guaranteeing the
# directory exists before the "200> ${_marker}.lock" redirect below, which
# would otherwise fail on a marker whose directory nothing has created yet.
# Always locks under fd 200: each call runs in its own subshell, so the fd
# number isn't shared state.
# _run_once <marker_file> <command...>
_run_once() {
    local _marker="$1"
    shift
    [ -f "${_marker}" ] && return 0
    mkdir -p "$(dirname "${_marker}")"
    (
        flock -x 200
        if [ ! -f "${_marker}" ]; then
            "$@" && touch "${_marker}"
        fi
    ) 200> "${_marker}.lock"
}

# Runs <command...> (which must write its single-line result into
# <value_file>) at most once via _run_once, then reads back and prints the
# cached result. The _run_once marker is "<value_file>.done", distinct from
# <value_file> itself: a producer's redirect into <value_file> creates/
# truncates it before its content is fully written, so using <value_file> as
# its own marker would let a concurrent _run_once fast path
# ([ -f "${_marker}" ] && return 0) observe it mid-write.
# _run_once_value <value_file> <command...>
_run_once_value() {
    local _value_file="$1"
    local _value
    shift
    _run_once "${_value_file}.done" "$@" || return 1
    IFS= read -r _value < "${_value_file}" || return 1
    printf '%s' "${_value}"
}

# Generates a test GPG key, writing its keyid into _keyid_file. chmod lives
# here (not in _ensure_gpg_key) so it only runs once, on the generate path,
# instead of on every call; the directory itself is already guaranteed to
# exist by _run_once's own mkdir -p.
_generate_gpg_keyid() {
    local _email="$1"
    local _keyid_file="$2"
    chmod 700 "${GNUPGHOME}"
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "${_email}" ed25519 sign never > /dev/null 2>&1 || return 1
    gpg --batch --list-secret-keys --with-colons "${_email}" \
        | awk -F: '/^sec/{print $5; exit}' > "${_keyid_file}"
    [ -s "${_keyid_file}" ]
}

# Generates a test GPG key on first use; reuses it on subsequent calls (within
# this run and across files, via the GNUPGHOME/keyid cache above).
_ensure_gpg_key() {
    local _email="$1"
    local _keyid_file="$2"
    _run_once_value "${_keyid_file}" _generate_gpg_keyid "${_email}" "${_keyid_file}"
}

# Second, distinct test GPG identity (different email), used only by
# identity.bats's signingkey-email-mismatch test. Cached the same way as the
# primary key, via the shared _ensure_gpg_key() helper.
OTHER_TEST_GIT_EMAIL="other@example.com"
OTHER_TEST_GIT_SIGNINGKEY=""

ensure_other_test_gpg_key() {
    # shellcheck disable=SC2034 # read by test/identity.bats via `load test_helper`
    OTHER_TEST_GIT_SIGNINGKEY="$(_ensure_gpg_key "${OTHER_TEST_GIT_EMAIL}" "${GNUPGHOME}/.other-keyid")"
}

# Generates the second identity before the primary key, not lazily in the one
# test that needs it: every keyring reader (make_repo, then check-identity)
# waits only on the primary key's marker, so a later lazy generation wrote the
# shared keyring while parallel tests read it, and their
# gpg --list-secret-keys failed transiently under bats --jobs.
ensure_test_gpg_key() {
    ensure_other_test_gpg_key || return 1
    TEST_GIT_SIGNINGKEY="$(_ensure_gpg_key "${TEST_GIT_EMAIL}" "${GNUPGHOME}/.keyid")"
}

# Pre-warms trivy's vulnerability DB once per bats run, via the same _run_once
# guard as _ensure_gpg_key above. trivy's own metadata.json write has no
# cross-process lock, so two of linters.bats's trivy tests updating the DB at
# the same moment under bats --jobs raced and corrupted the loser's read
# (json decode error: EOF). Warming the shared cache once before either test's
# own trivy invocation means both see an already-fresh DB and never write.
ensure_trivy_db_warm() {
    command -v trivy > /dev/null 2>&1 || return 0
    _run_once "${BATS_RUN_TMPDIR}/.trivy-db-warm" trivy fs --download-db-only --quiet "${BATS_RUN_TMPDIR}"
}

# Fails the current test with a message on stderr. bats-assert's `fail` is not
# loaded by this suite, so tests that need a descriptive failure use this.
fail_test() {
    printf '%s\n' "$*" >&2
    return 1
}

# link_host_tool <tool> <dir>
# Symlinks the host's <tool> into <dir>, so a test PATH limited to fakes can
# still run it. Fails naming the tool when the host has none, rather than
# leaving a dangling link that surfaces later as a misleading
# command-not-found.
link_host_tool() {
    local _real
    _real="$(type -P "$1")" \
        || fail_test "link_host_tool: host tool '$1' not found on PATH" \
        || return 1
    ln -s "${_real}" "$2/$1"
}

# write_tool <dir> <command> [body]
# Writes a stand-in executable <dir>/<command>, readable by every user, whose
# script runs <body> (default: exit 0). The host chmod is used, because some
# suites put a fake chmod on PATH.
write_tool() {
    mkdir -p "$1"
    printf '#!/bin/sh\n%s\n' "${3:-exit 0}" > "$1/$2"
    "$(type -P chmod)" 0755 "$1/$2"
}

# write_fake_sudo <dir>
# Writes a fake sudo to "<dir>/sudo" that never elevates. It appends each
# call's arguments to $FAKE_SUDO_LOG when that is set, fails when the command
# it is asked to run is the one named in $FAKE_SUDO_FAIL_COMMAND, and otherwise
# runs the command as the current user with FAKE_SUDO_AS_ROOT=1 exported, so a
# fake it runs can act as root would. Anything that must not really run (e.g. a
# write into /usr/local/bin) needs its own fake earlier on PATH.
write_fake_sudo() {
    local _dir="$1"
    mkdir -p "${_dir}"
    cat > "${_dir}/sudo" <<'EOF'
#!/bin/sh
[ -z "${FAKE_SUDO_LOG:-}" ] || printf '%s\n' "$*" >> "$FAKE_SUDO_LOG"
[ "$1" != "${FAKE_SUDO_FAIL_COMMAND:-}" ] || exit 1
FAKE_SUDO_AS_ROOT=1
export FAKE_SUDO_AS_ROOT
exec "$@"
EOF
    chmod +x "${_dir}/sudo"
}

# fail_with_run_output <status> <output> <expected status>
# Prints a run's exit status and output to the TAP stream, so an unexpected
# result is diagnosable, and fails.
fail_with_run_output() {
    printf '# exit status: %s (expected %s)\n# output:\n' "$1" "$3" >&3
    printf '%s\n' "$2" | sed 's/^/# /' >&3
    return 1
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

# Commits the given path through a no-op hooksPath, so the file is tracked in
# HEAD without the hook under test running during setup, then points
# core.hooksPath back at HOOKS_DIR as make_repo configured it.
commit_without_hooks() {
    local _repo="$1"
    local _path="$2"
    mkdir -p "${_repo}/.no-hooks"
    git -C "${_repo}" config core.hooksPath "${_repo}/.no-hooks"
    git -C "${_repo}" add -- "${_path}"
    git -C "${_repo}" commit --quiet -m baseline
    git -C "${_repo}" config core.hooksPath "${HOOKS_DIR}"
}

# Succeeds when the given path is in the given repo's index.
is_tracked() {
    [ -n "$(git -C "$1" ls-files -- "$2")" ]
}

# Succeeds when the given path is not in the given repo's index. A bare
# `! is_tracked` never fails a bats test (bash's errexit ignores negated
# commands), so negative index checks need their own predicate.
is_untracked() {
    [ -z "$(git -C "$1" ls-files -- "$2")" ]
}

# run_in_hook_env <repo> <path> [NAME=value ...] <command> [arg ...]
# Runs <command> from <repo> with PATH set to <path> and any NAME=value
# assignments added, in the environment every run_hook* helper gives the hook.
# Sets $status and $output via bats run.
# bats 1.10.x (Ubuntu 24.04) does not export bats_readlinkf from its wrapper
# when invoked from a sh parent process; without it bats-exec-file cannot locate
# bats-exec-test.  Defining and exporting bats_readlinkf here ensures the inner
# bats library always resolves its own path correctly (defence-in-depth alongside
# the same fix in src/scripts/run-bats).
# The four per-run tmpdir vars are also cleared so the inner bats starts with a
# fresh tmpdir hierarchy rather than re-using the outer suite directories.
# HOOKS_REPO_DIR_TEST_OVERRIDE, if exported by the caller (see freshness.bats), is
# inherited by bash -c like any other exported variable, and this applies to every
# run_hook* helper in this file.
run_in_hook_env() {
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" "${@:3}"
    ' _ "$@"
}

# Runs the hook in the given repo directory using TEST_PATH (dotnet stripped
# when not at the expected location).  Sets $status and $output via bats run.
run_hook() {
    run_in_hook_env "$1" "${TEST_PATH}" sh "${HOOK}"
}

# Runs the hook with IS_AMEND_TEST_OVERRIDE=1, simulating the invoking git
# commit having been run with --amend (see is_amend in src/hooks/pre-commit —
# the real signal is the parent process's own command line, which this
# bash -c/sh invocation can never make look like `git commit --amend`).
run_hook_as_amend() {
    run_in_hook_env "$1" "${TEST_PATH}" IS_AMEND_TEST_OVERRIDE=1 sh "${HOOK}"
}

# Runs the hook in --all-files (baseline) mode using TEST_PATH.
# Sets $status and $output via bats run.
run_hook_all_files() {
    run_in_hook_env "$1" "${TEST_PATH}" sh "${HOOK}" --all-files
}

# Runs the hook with a custom PATH and XDG_CACHE_HOME (for freshness tests).
# run_hook_env <repo> <path> <xdg_cache_home>
run_hook_env() {
    run_in_hook_env "$1" "$2" XDG_CACHE_HOME="$3" sh "${HOOK}"
}

# Runs the hook in the given repo directory with HOOKS_REPO_DIR_TEST_OVERRIDE set to the
# repo path so that the hook's protected-file guard fires as if this were the hooks repo.
run_hook_as_hooks_repo() {
    run_in_hook_env "$1" "${TEST_PATH}" HOOKS_REPO_DIR_TEST_OVERRIDE="$1" sh "${HOOK}"
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
    run_in_hook_env "$1" "$2" CLAUDECODE=1 XDG_CACHE_HOME="$3" sh "${HOOK}"
}

# run_isolated <cwd> <path> <command>...
# Runs <command> from <cwd> with PATH set to <path>, outside this bats run's
# own environment. Use it for every run that can reach an inner bats suite
# (the full hook, or run-bats directly). XDG_RUNTIME_DIR is unset because
# every fixture repo resolves to the same $XDG_RUNTIME_DIR/_local/repo/bats,
# which run-bats wipes before each run; under bats --jobs that would delete a
# concurrent test's tmpdir, while the /tmp fallback gives each run its own
# bats-run-XXXXXX. It is unset only here, not in run_in_hook_env, because gpg and
# other tools the remaining tests reach rely on it. RUN_BATS_FULL is unset so a
# value exported by the caller cannot force run-bats to run the full suite.
run_isolated() {
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR XDG_RUNTIME_DIR RUN_BATS_FULL
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        _path="$2"
        shift 2
        env PATH="${_path}" "$@"
    ' _ "$@"
}

# run_bats_all_files <cwd> [path]
# Runs run-bats --all-files from <cwd> through run_isolated, with PATH set to
# [path] (default TEST_PATH).
run_bats_all_files() {
    run_isolated "$1" "${2:-${TEST_PATH}}" "${REPO_DIR}/src/scripts/run-bats" --all-files
}
