#!/usr/bin/env bats
# Dotnet install-location acceptance tests.
# The hook rejects dotnet at $HOME/.dotnet/dotnet (corrupt user install) and
# at any path other than /usr/share/dotnet/dotnet.

load test_helper

@test "dotnet at HOME/.dotnet/dotnet is rejected" {
    local T FAKE_HOME
    FAKE_HOME="${BATS_TEST_TMPDIR}/fake_home"
    mkdir -p "${FAKE_HOME}/.dotnet"
    printf '#!/bin/sh\necho fake dotnet\n' > "${FAKE_HOME}/.dotnet/dotnet"
    chmod +x "${FAKE_HOME}/.dotnet/dotnet"
    T="$(make_repo feature/corrupt-dotnet-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run bash -c 'cd "$1" && unset CLAUDECODE && env PATH="$2" HOME="$3" sh "$4"' _ "${T}" "${TEST_PATH}" "${FAKE_HOME}" "${HOOK}"
    [ "${status}" -eq 1 ]
}

@test "dotnet at wrong path is rejected" {
    if [ -z "${_ACTUAL_DOTNET_BIN}" ]; then
        skip "dotnet not installed"
    fi
    if [ "${_ACTUAL_DOTNET_REAL}" = "${_EXPECTED_DOTNET}" ]; then
        skip "dotnet is already at expected path"
    fi
    local T
    T="$(make_repo feature/wrong-dotnet-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run bash -c 'cd "$1" && unset CLAUDECODE && sh "$2"' _ "${T}" "${HOOK}"
    [ "${status}" -eq 1 ]
}

@test "dotnet at correct path passes" {
    if [ "${_ACTUAL_DOTNET_REAL}" != "${_EXPECTED_DOTNET}" ]; then
        skip "dotnet not at ${_EXPECTED_DOTNET}"
    fi
    local T _CORRECT_PATH _EXPECTED_DOTNET_DIR
    _EXPECTED_DOTNET_DIR="$(dirname "${_EXPECTED_DOTNET}")"
    _CORRECT_PATH="${_EXPECTED_DOTNET_DIR}:${TEST_PATH}"
    T="$(make_repo feature/correct-dotnet-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run bash -c 'cd "$1" && unset CLAUDECODE && env PATH="$2" sh "$3"' _ "${T}" "${_CORRECT_PATH}" "${HOOK}"
    [ "${status}" -eq 0 ]
}
