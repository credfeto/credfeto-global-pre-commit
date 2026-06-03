#!/usr/bin/env bats
# Freshness-check acceptance tests.
# The hook reads $HOOKS_REPO_DIR/.env for a SHA= line and compares it against
# the published SHA fetched via curl (cached for one hour).  Tests here stub
# curl and place a .env file in the repo root; teardown removes it.
#
# Stub binaries are created inside the repo tree (test/.stub.*) rather than
# under BATS_TEST_TMPDIR because /tmp is mounted noexec on this system.

load test_helper

# Directory to hold per-test stub binaries (inside repo tree, so executable).
STUB_BIN=""

setup() {
    STUB_BIN="$(mktemp -d "${REPO_DIR}/test/.stub.XXXXXX")"
}

teardown() {
    rm -f "${REPO_DIR}/.env"
    [ -n "${STUB_BIN}" ] && rm -rf "${STUB_BIN}"
}

@test ".env absent means freshness check is skipped and hook passes" {
    local T
    T="$(make_repo feature/freshness-no-env-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test ".env SHA matches published SHA so hook passes" {
    printf '#!/bin/sh\nprintf "abcdef1234567890"\n' > "${STUB_BIN}/curl"
    chmod +x "${STUB_BIN}/curl"
    local FAKE_CACHE T
    FAKE_CACHE="${BATS_TEST_TMPDIR}/fake_cache"
    mkdir -p "${FAKE_CACHE}"
    printf 'SHA=abcdef1234567890\n' > "${REPO_DIR}/.env"
    T="$(make_repo feature/freshness-match-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_env "${T}" "${STUB_BIN}:${TEST_PATH}" "${FAKE_CACHE}"
    [ "${status}" -eq 0 ]
}

@test ".env SHA is stale so hook rejects the commit" {
    printf '#!/bin/sh\nprintf "1234567890abcdef"\n' > "${STUB_BIN}/curl"
    chmod +x "${STUB_BIN}/curl"
    local FAKE_CACHE T
    FAKE_CACHE="${BATS_TEST_TMPDIR}/fake_cache"
    mkdir -p "${FAKE_CACHE}"
    printf 'SHA=0000111100001111\n' > "${REPO_DIR}/.env"
    T="$(make_repo feature/freshness-stale-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_env "${T}" "${STUB_BIN}:${TEST_PATH}" "${FAKE_CACHE}"
    [ "${status}" -eq 1 ]
}

@test "curl failure means freshness check is skipped and hook passes" {
    printf '#!/bin/sh\nexit 6\n' > "${STUB_BIN}/curl"
    chmod +x "${STUB_BIN}/curl"
    local FAKE_CACHE T
    FAKE_CACHE="${BATS_TEST_TMPDIR}/fake_cache"
    mkdir -p "${FAKE_CACHE}"
    printf 'SHA=some-installed-sha\n' > "${REPO_DIR}/.env"
    T="$(make_repo feature/freshness-curl-fail-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_env "${T}" "${STUB_BIN}:${TEST_PATH}" "${FAKE_CACHE}"
    [ "${status}" -eq 0 ]
}
