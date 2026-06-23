#!/usr/bin/env bats
# Freshness-check acceptance tests.
# The hook reads $HOOKS_REPO_DIR/.env for a SHA= line and compares it against
# the published SHA fetched via curl (cached for one hour).  Tests here stub
# curl and place a .env file in the repo root; teardown removes it.
#
# Stub binaries and the fake XDG cache are created inside the repo tree
# (test/.stub.* and test/.cache.*) rather than under BATS_TEST_TMPDIR because:
#   - /tmp is mounted noexec on this system (stubs must be executable).
#   - bats 1.10.x does not reset BATS_TEST_TMPDIR between tests in the same
#     file, so deriving FAKE_CACHE from it caused the SHA written to the cache
#     by one test to be read by the next, producing spurious failures.
# Using mktemp -d in the repo tree guarantees a unique, fresh directory for
# every test regardless of the BATS_TEST_TMPDIR lifecycle.

load test_helper

# Directory to hold per-test stub binaries (inside repo tree, so executable).
STUB_BIN=""
# Fresh XDG_CACHE_HOME per test so cached SHAs never bleed between tests.
FAKE_CACHE=""

setup() {
    STUB_BIN="$(mktemp -d "${REPO_DIR}/test/.stub.XXXXXX")"
    FAKE_CACHE="$(mktemp -d "${REPO_DIR}/test/.cache.XXXXXX")"
}

teardown() {
    rm -f "${REPO_DIR}/.env"
    [ -n "${STUB_BIN}" ] && rm -rf "${STUB_BIN}"
    [ -n "${FAKE_CACHE}" ] && rm -rf "${FAKE_CACHE}"
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
    local T
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
    local T
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
    local T
    printf 'SHA=some-installed-sha\n' > "${REPO_DIR}/.env"
    T="$(make_repo feature/freshness-curl-fail-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_env "${T}" "${STUB_BIN}:${TEST_PATH}" "${FAKE_CACHE}"
    [ "${status}" -eq 0 ]
}

_in_container() {
    [ -f /.dockerenv ] || [ -f /run/.containerenv ] || [ -n "${container:-}" ] \
        || grep -q 'docker\|containerd\|kubepods' /proc/1/cgroup 2>/dev/null
}

@test "AI agent in container with stale SHA passes (freshness check skipped)" {
    # Requires an OCI container environment (Docker, Podman, etc.).
    if ! _in_container; then
        skip "not running inside a container"
    fi
    printf '#!/bin/sh\nprintf "1234567890abcdef"\n' > "${STUB_BIN}/curl"
    chmod +x "${STUB_BIN}/curl"
    local T
    printf 'SHA=0000111100001111\n' > "${REPO_DIR}/.env"
    T="$(make_repo feature/freshness-container-agent-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_env_as_agent "${T}" "${STUB_BIN}:${TEST_PATH}" "${FAKE_CACHE}"
    [ "${status}" -eq 0 ]
}

@test "non-AI agent in container with stale SHA is rejected" {
    if ! _in_container; then
        skip "not running inside a container"
    fi
    printf '#!/bin/sh\nprintf "1234567890abcdef"\n' > "${STUB_BIN}/curl"
    chmod +x "${STUB_BIN}/curl"
    local T
    printf 'SHA=0000111100001111\n' > "${REPO_DIR}/.env"
    T="$(make_repo feature/freshness-container-noagent-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_env "${T}" "${STUB_BIN}:${TEST_PATH}" "${FAKE_CACHE}"
    [ "${status}" -eq 1 ]
}
