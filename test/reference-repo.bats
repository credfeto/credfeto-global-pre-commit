#!/usr/bin/env bats
# Acceptance tests for src/scripts/check-reference-repo and its wiring into
# the pre-commit and pre-push hooks:
# - a repository whose resolved top level is the reference root
#   ($REFERENCE_REPO_ROOT, default $HOME/work/reference) or beneath it is
#   rejected, however it is reached (subdirectory, symlinked checkout,
#   symlinked root)
# - any other repository, including a sibling of the root sharing its prefix,
#   passes
#
# Direct script runs use a fake HOME so the default root is exercised; hook
# runs keep the real HOME (gpg and the linters need it) and set
# REFERENCE_REPO_ROOT instead.

load test_helper

CHECK_REFERENCE_REPO="${REPO_DIR}/src/scripts/check-reference-repo"
PRE_PUSH_HOOK="${HOOKS_DIR}/pre-push"

setup() {
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${FAKE_HOME}"
}

# Creates a bare-minimum git repository at "$1".
init_repo() {
    mkdir -p "$1"
    git -C "$1" init --quiet
}

# run_check <cwd> [REFERENCE_REPO_ROOT]
# Runs check-reference-repo from <cwd> with HOME set to FAKE_HOME and
# REFERENCE_REPO_ROOT set to the second argument, or unset when it is omitted.
# Sets $status and $output via bats run.
run_check() {
    run bash -c '
        cd "$1"
        unset REFERENCE_REPO_ROOT
        [ -z "$5" ] || export REFERENCE_REPO_ROOT="$5"
        env PATH="$2" HOME="$3" sh "$4"
    ' _ "$1" "${TEST_PATH}" "${FAKE_HOME}" "${CHECK_REFERENCE_REPO}" "${2:-}"
}

# run_pre_push <repo> <remote ref> [REFERENCE_REPO_ROOT]
# Runs the pre-push hook in <repo>, feeding it one ref line for <remote ref>
# on stdin as git does. Sets $status and $output via bats run.
run_pre_push() {
    run bash -c '
        cd "$1"
        unset CLAUDECODE REFERENCE_REPO_ROOT
        [ -z "$5" ] || export REFERENCE_REPO_ROOT="$5"
        printf "refs/heads/feature 1111111111111111111111111111111111111111 %s 0000000000000000000000000000000000000000\n" "$4" \
            | env PATH="$2" sh "$3" origin git@example.com:owner/repo.git
    ' _ "$1" "${TEST_PATH}" "${PRE_PUSH_HOOK}" "$2" "${3:-}"
}

assert_rejected_naming() {
    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"reference repository rule"* ]]
    [[ "${output}" == *"$1"* ]]
}

assert_passed() {
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
}

# ── check-reference-repo ──────────────────────────────────────────────────────

@test "commit from the top level of a reference clone is rejected" {
    init_repo "${FAKE_HOME}/work/reference/myrepo"
    run_check "${FAKE_HOME}/work/reference/myrepo"
    assert_rejected_naming "${FAKE_HOME}/work/personal/myrepo"
}

@test "commit from a subdirectory of a reference clone is rejected" {
    init_repo "${FAKE_HOME}/work/reference/myrepo"
    mkdir -p "${FAKE_HOME}/work/reference/myrepo/src/deep"
    run_check "${FAKE_HOME}/work/reference/myrepo/src/deep"
    assert_rejected_naming "${FAKE_HOME}/work/personal/myrepo"
}

@test "commit through a symlink to a reference clone is rejected" {
    init_repo "${FAKE_HOME}/work/reference/myrepo"
    mkdir -p "${FAKE_HOME}/elsewhere"
    ln -s "${FAKE_HOME}/work/reference/myrepo" "${FAKE_HOME}/elsewhere/link"
    run_check "${FAKE_HOME}/elsewhere/link"
    assert_rejected_naming "${FAKE_HOME}/work/personal/myrepo"
}

@test "commit in a reference clone is rejected when the reference root is a symlink" {
    init_repo "${FAKE_HOME}/real-reference/myrepo"
    mkdir -p "${FAKE_HOME}/work"
    ln -s "${FAKE_HOME}/real-reference" "${FAKE_HOME}/work/reference"
    run_check "${FAKE_HOME}/real-reference/myrepo"
    assert_rejected_naming "${FAKE_HOME}/work/personal/myrepo"
}

@test "commit through a symlinked reference root is rejected" {
    init_repo "${FAKE_HOME}/real-reference/myrepo"
    mkdir -p "${FAKE_HOME}/work"
    ln -s "${FAKE_HOME}/real-reference" "${FAKE_HOME}/work/reference"
    run_check "${FAKE_HOME}/work/reference/myrepo"
    assert_rejected_naming "${FAKE_HOME}/work/personal/myrepo"
}

@test "commit in a repository that is the reference root itself is rejected" {
    init_repo "${FAKE_HOME}/work/reference"
    run_check "${FAKE_HOME}/work/reference"
    assert_rejected_naming "${FAKE_HOME}/work/personal/<repo>"
}

@test "commit in a personal checkout passes" {
    mkdir -p "${FAKE_HOME}/work/reference"
    init_repo "${FAKE_HOME}/work/personal/myrepo"
    run_check "${FAKE_HOME}/work/personal/myrepo"
    assert_passed
}

@test "commit in a sibling directory sharing the reference root's prefix passes" {
    mkdir -p "${FAKE_HOME}/work/reference"
    init_repo "${FAKE_HOME}/work/reference-old/myrepo"
    run_check "${FAKE_HOME}/work/reference-old/myrepo"
    assert_passed
}

@test "commit passes when the reference root does not exist" {
    init_repo "${FAKE_HOME}/work/personal/myrepo"
    run_check "${FAKE_HOME}/work/personal/myrepo"
    assert_passed
}

@test "commit in a bare repository passes" {
    mkdir -p "${FAKE_HOME}/work/reference/myrepo.git"
    git -C "${FAKE_HOME}/work/reference/myrepo.git" init --quiet --bare
    run_check "${FAKE_HOME}/work/reference/myrepo.git"
    assert_passed
}

@test "REFERENCE_REPO_ROOT moves the reference root" {
    init_repo "${FAKE_HOME}/custom/myrepo"
    run_check "${FAKE_HOME}/custom/myrepo" "${FAKE_HOME}/custom"
    assert_rejected_naming "${FAKE_HOME}/work/personal/myrepo"
}

@test "REFERENCE_REPO_ROOT replaces the default reference root" {
    mkdir -p "${FAKE_HOME}/custom"
    init_repo "${FAKE_HOME}/work/reference/myrepo"
    run_check "${FAKE_HOME}/work/reference/myrepo" "${FAKE_HOME}/custom"
    assert_passed
}

# ── wiring into the pre-commit hook ───────────────────────────────────────────

@test "pre-commit hook rejects a commit in a reference clone" {
    local T
    T="$(make_repo feature/reference-repo-hook-test)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_in_hook_env "${T}" "${TEST_PATH}" REFERENCE_REPO_ROOT="${BATS_TEST_TMPDIR}" sh "${HOOK}"
    assert_rejected_naming "commit in a read-only reference clone"
}

@test "pre-commit hook names the reference rule for a reference clone on main" {
    local T
    T="$(make_repo main)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_in_hook_env "${T}" "${TEST_PATH}" REFERENCE_REPO_ROOT="${BATS_TEST_TMPDIR}" sh "${HOOK}"
    assert_rejected_naming "commit in a read-only reference clone"
    [[ "${output}" != *"direct commits to"* ]]
}

@test "pre-commit hook passes a commit outside the reference root" {
    local T
    T="$(make_repo feature/reference-repo-hook-valid-test)"
    mkdir -p "${BATS_TEST_TMPDIR}/reference"
    # A no-op project .pre-commit-config.yaml keeps this test scoped to the
    # hook's wiring, as in identity.bats.
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add .pre-commit-config.yaml file.txt
    run_in_hook_env "${T}" "${TEST_PATH}" REFERENCE_REPO_ROOT="${BATS_TEST_TMPDIR}/reference" sh "${HOOK}"
    assert_passed
}

# ── wiring into the pre-push hook ─────────────────────────────────────────────

@test "pre-push hook rejects a push from a reference clone" {
    init_repo "${BATS_TEST_TMPDIR}/reference/myrepo"
    run_pre_push "${BATS_TEST_TMPDIR}/reference/myrepo" refs/heads/feature "${BATS_TEST_TMPDIR}/reference"
    assert_rejected_naming "push from a read-only reference clone"
}

@test "pre-push hook passes a feature-branch push outside the reference root" {
    mkdir -p "${BATS_TEST_TMPDIR}/reference"
    init_repo "${BATS_TEST_TMPDIR}/personal/myrepo"
    run_pre_push "${BATS_TEST_TMPDIR}/personal/myrepo" refs/heads/feature "${BATS_TEST_TMPDIR}/reference"
    assert_passed
}

@test "pre-push hook still blocks a push to main outside the reference root" {
    mkdir -p "${BATS_TEST_TMPDIR}/reference"
    init_repo "${BATS_TEST_TMPDIR}/personal/myrepo"
    run_pre_push "${BATS_TEST_TMPDIR}/personal/myrepo" refs/heads/main "${BATS_TEST_TMPDIR}/reference"
    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"Direct pushes to refs/heads/main are not permitted"* ]]
}
