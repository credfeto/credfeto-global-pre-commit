#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

SHELLCHECK_CONFIG='repos:
  - repo: local
    hooks:
      - id: shellcheck
        name: shellcheck
        entry: shellcheck
        args: [--shell=sh, --severity=warning]
        language: system
        types: [shell]
'

# Mirrors the production shellcheck hooks' flags (no shell or severity
# override) so the sourced-library tests below exercise the real hook shape.
SHELLCHECK_SOURCED_CONFIG='repos:
  - repo: local
    hooks:
      - id: shellcheck
        name: shellcheck
        entry: shellcheck
        args: [-x, --check-sourced, --source-path=SCRIPTDIR]
        language: system
        types: [shell]
'

SHELLCHECK_LIBRARIES_CONFIG="repos:
  - repo: local
    hooks:
      - id: shellcheck-libraries
        name: shellcheck (shell libraries)
        entry: ${REPO_DIR}/src/scripts/run-shellcheck-libraries
        language: system
        files: (^|/)[^/.]+\$
        types: [text]
        exclude_types: [shell]
"

# shellcheck disable=SC2016
BROKEN_SHELL_LIBRARY='# shellcheck shell=bash
greet() {
    local now=$(date)
    echo "$now"
}
'

# shellcheck disable=SC2016
CLEAN_SHELL_LIBRARY='# shellcheck shell=bash
greet() {
    local now
    now=$(date)
    echo "$now"
}
'

# shellcheck disable=SC2016
SOURCING_SCRIPT='#!/bin/bash
source "$(dirname "$0")/lib/common"
greet
'

# ── shellcheck ────────────────────────────────────────────────────────────────

@test "broken shell script (SC2086/SC3014) is rejected" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-sh-test)"
    printf '%s' "${SHELLCHECK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nvar=hello\n[ $var == x ] && echo "match"\n' > "${T}/test.sh"
    git -C "${T}" add .pre-commit-config.yaml test.sh
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean shell script passes" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/clean-sh-test)"
    printf '%s' "${SHELLCHECK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nvar=hello\nif [ "$var" = "x" ]; then\n    echo "match"\nfi\n' > "${T}/test.sh"
    git -C "${T}" add .pre-commit-config.yaml test.sh
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# The library is extensionless with no shebang, so the shell-typed hook never
# selects it directly: its finding can only surface through --check-sourced.
@test "shell script sourcing a broken library is rejected" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/sourced-broken-lib-test)"
    printf '%s' "${SHELLCHECK_SOURCED_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/lib"
    printf '%s' "${BROKEN_SHELL_LIBRARY}" > "${T}/lib/common"
    printf '%s' "${SOURCING_SCRIPT}" > "${T}/main.sh"
    git -C "${T}" add .pre-commit-config.yaml lib/common main.sh
    run_hook "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"lib/common"* ]]
}

@test "shell script sourcing a clean library passes" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/sourced-clean-lib-test)"
    printf '%s' "${SHELLCHECK_SOURCED_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/lib"
    printf '%s' "${CLEAN_SHELL_LIBRARY}" > "${T}/lib/common"
    printf '%s' "${SOURCING_SCRIPT}" > "${T}/main.sh"
    git -C "${T}" add .pre-commit-config.yaml lib/common main.sh
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "standalone shell library with a shellcheck directive and a finding is rejected" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/standalone-broken-lib-test)"
    printf '%s' "${SHELLCHECK_LIBRARIES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/lib"
    printf '%s' "${BROKEN_SHELL_LIBRARY}" > "${T}/lib/common"
    git -C "${T}" add .pre-commit-config.yaml lib/common
    run_hook "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"lib/common"* ]]
}

# notes is extensionless so the hook's files: filter offers it to the wrapper;
# it would fail shellcheck (no shebang or directive) if the wrapper linted every
# offered file instead of only directive-carrying libraries.
@test "standalone clean shell library with a shellcheck directive passes" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/standalone-clean-lib-test)"
    printf '%s' "${SHELLCHECK_LIBRARIES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/lib"
    printf '%s' "${CLEAN_SHELL_LIBRARY}" > "${T}/lib/common"
    # shellcheck disable=SC2016
    printf 'echo $unquoted\n' > "${T}/notes"
    git -C "${T}" add .pre-commit-config.yaml lib/common notes
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# Covers the wrapper's no-qualifying-files exit: no staged file carries a directive.
@test "text files without a shellcheck directive are skipped by the library hook" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/no-directive-lib-test)"
    printf '%s' "${SHELLCHECK_LIBRARIES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf 'echo $unquoted\n' > "${T}/notes"
    git -C "${T}" add .pre-commit-config.yaml notes
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
