#!/usr/bin/env bats
# Acceptance tests for src/scripts/check-identity:
# - git user.email must be set and not the known-bad default identity
# - commit.gpgsign must be enabled
# - gpg must be installed with a secret key for user.email
# - user.signingkey must be set, present in the keyring, and associated with
#   user.email
#
# make_repo() already configures a valid identity and signing key (see
# test_helper.bash), so each negative test starts from that baseline and
# overrides just the one setting under test.

load test_helper

CHECK_IDENTITY="${REPO_DIR}/src/scripts/check-identity"

# Second, distinct test key (different email) used only by the
# signingkey-email-mismatch test below.
OTHER_EMAIL="other@example.com"
ensure_other_test_gpg_key() {
    OTHER_SIGNINGKEY="$(gpg --batch --list-secret-keys --with-colons "${OTHER_EMAIL}" 2>/dev/null \
        | awk -F: '/^sec/{print $5; exit}')"
    if [ -n "${OTHER_SIGNINGKEY}" ]; then
        return 0
    fi
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "${OTHER_EMAIL}" ed25519 sign never > /dev/null 2>&1
    OTHER_SIGNINGKEY="$(gpg --batch --list-secret-keys --with-colons "${OTHER_EMAIL}" \
        | awk -F: '/^sec/{print $5; exit}')"
}

# Runs check-identity inside "$1". Sets $status and $output via bats run.
run_check_identity() {
    local _repo="$1"
    run bash -c 'cd "$1" && env PATH="$2" sh "$3"' \
        _ "${_repo}" "${TEST_PATH}" "${CHECK_IDENTITY}"
}

@test "valid identity and signing key passes" {
    local T
    T="$(make_repo feature/identity-valid-test)"
    run_check_identity "${T}"
    [ "${status}" -eq 0 ]
}

@test "missing user.email is rejected" {
    local T
    T="$(make_repo feature/identity-no-email-test)"
    git -C "${T}" config --unset user.email
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"user.email is not set"* ]]
}

@test "known-bad default identity is rejected" {
    local T
    T="$(make_repo feature/identity-bad-default-test)"
    git -C "${T}" config user.email "andy@nanoclaw.ai"
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"wrong identity"* ]]
}

@test "gpgsign disabled is rejected" {
    local T
    T="$(make_repo feature/identity-no-gpgsign-test)"
    git -C "${T}" config commit.gpgsign false
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"GPG signing is not enabled"* ]]
}

@test "missing user.signingkey is rejected" {
    local T
    T="$(make_repo feature/identity-no-signingkey-test)"
    git -C "${T}" config --unset user.signingkey
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"user.signingkey is not set"* ]]
}

@test "signingkey not found in keyring is rejected" {
    local T
    T="$(make_repo feature/identity-unknown-signingkey-test)"
    git -C "${T}" config user.signingkey "0000000000000000"
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"not found in GPG keyring"* ]]
}

@test "signingkey belonging to a different email is rejected" {
    ensure_other_test_gpg_key
    local T
    T="$(make_repo feature/identity-mismatched-signingkey-test)"
    git -C "${T}" config user.signingkey "${OTHER_SIGNINGKEY}"
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"is not associated with"* ]]
}

@test "no GPG secret key for user.email is rejected" {
    local T
    T="$(make_repo feature/identity-no-secret-key-test)"
    git -C "${T}" config user.email "nokey@example.com"
    run_check_identity "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"no GPG secret key found"* ]]
}

# ── wiring into the hook ──────────────────────────────────────────────────────

@test "hook rejects a commit with a broken identity" {
    local T
    T="$(make_repo feature/identity-hook-test)"
    git -C "${T}" config --unset user.email
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "hook passes with a valid identity" {
    local T
    T="$(make_repo feature/identity-hook-valid-test)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
