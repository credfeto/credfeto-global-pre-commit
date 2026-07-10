#!/usr/bin/env bats
# Acceptance tests for the --all-files baseline mode.
# Default (no-arg) invocation must stay byte-for-byte unchanged; --all-files
# must run every category check against the full tracked tree (git ls-files)
# regardless of what is staged, and skip the mid-commit-only guards.

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

# ── nothing staged ────────────────────────────────────────────────────────────

@test "all-files mode on a clean repo with nothing staged passes" {
    local T
    T="$(make_repo feature/all-files-clean-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# Test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    git -C "${T}" commit --quiet --no-verify -m seed
    run_hook_all_files "${T}"
    [ "${status}" -eq 0 ]
}

@test "default mode still aborts with nothing staged" {
    local T
    T="$(make_repo feature/all-files-default-still-empty-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# Test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    git -C "${T}" commit --quiet --no-verify -m seed
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── branch guard ──────────────────────────────────────────────────────────────

@test "all-files mode on main branch passes (branch guard skipped)" {
    local T
    T="$(make_repo main)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# Test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    git -C "${T}" commit --quiet --no-verify -m seed
    run_hook_all_files "${T}"
    [ "${status}" -eq 0 ]
}

@test "default mode on main branch is still rejected" {
    local T
    T="$(make_repo main)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── whole-tree detection ──────────────────────────────────────────────────────

@test "all-files mode detects a tracked but unstaged lint violation" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/all-files-lint-violation-test)"
    printf '%s' "${SHELLCHECK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nvar=hello\n[ $var == x ] && echo "match"\n' > "${T}/bad.sh"
    git -C "${T}" add .pre-commit-config.yaml bad.sh
    git -C "${T}" commit --quiet --no-verify -m seed
    run_hook_all_files "${T}"
    [ "${status}" -eq 1 ]
}

@test "all-files mode passes when tracked files are clean" {
    if ! command -v shellcheck > /dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/all-files-lint-clean-test)"
    printf '%s' "${SHELLCHECK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nvar=hello\nif [ "$var" = "x" ]; then\n    echo "match"\nfi\n' > "${T}/good.sh"
    git -C "${T}" add .pre-commit-config.yaml good.sh
    git -C "${T}" commit --quiet --no-verify -m seed
    run_hook_all_files "${T}"
    [ "${status}" -eq 0 ]
}

# ── unknown argument ──────────────────────────────────────────────────────────

@test "unknown argument is rejected" {
    local T
    T="$(make_repo feature/all-files-unknown-arg-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# Test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" sh "$3" --bogus
    ' _ "${T}" "${TEST_PATH}" "${HOOK}"
    [ "${status}" -eq 1 ]
}
