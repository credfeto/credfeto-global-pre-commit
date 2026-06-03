#!/usr/bin/env bats
# Acceptance tests for the bats pre-commit hook.
# Verifies that a failing bats test blocks the commit and a passing one allows it.

load test_helper

# ── bats ─────────────────────────────────────────────────────────────────────

@test "failing bats test blocks commit" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/failing-bats-test)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "always fails" {\n  false\n}\n' > "${T}/test/fail.bats"
    git -C "${T}" add .pre-commit-config.yaml test/fail.bats
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "passing bats tests allow commit" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/passing-bats-test)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "always passes" {\n  true\n}\n' > "${T}/test/pass.bats"
    git -C "${T}" add .pre-commit-config.yaml test/pass.bats
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "bats hook passes when no test directory exists" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/no-test-dir-bats)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '#!/usr/bin/env bats\n@test "stub" {\n  true\n}\n' > "${T}/stub.bats"
    git -C "${T}" add .pre-commit-config.yaml stub.bats
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
