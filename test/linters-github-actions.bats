#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

ACTIONLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: actionlint
        name: actionlint
        entry: actionlint
        language: system
        files: ^\.github/workflows/.*\.(yml|yaml)$
        require_serial: true
'

COMPOSITE_ACTION_LINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: composite-action-lint
        name: composite-action-lint
        entry: composite-action-lint
        language: system
        files: ^\.github/actions/.*\.(yml|yaml)$
'

# ── actionlint ────────────────────────────────────────────────────────────────

@test "broken GitHub Actions workflow (undefined step output) is rejected" {
    if ! command -v actionlint > /dev/null 2>&1; then
        skip "actionlint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-workflow-test)"
    printf '%s' "${ACTIONLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/workflows"
    printf "name: Broken\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo \"\${{ steps.undefined.outputs.value }}\"\n" > "${T}/.github/workflows/broken.yml"
    git -C "${T}" add .pre-commit-config.yaml ".github/workflows/broken.yml"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid GitHub Actions workflow passes" {
    if ! command -v actionlint > /dev/null 2>&1; then
        skip "actionlint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-workflow-test)"
    printf '%s' "${ACTIONLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/workflows"
    printf 'name: Valid\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "Hello World"\n' > "${T}/.github/workflows/valid.yml"
    git -C "${T}" add .pre-commit-config.yaml ".github/workflows/valid.yml"
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "broken workflow among several is still rejected under require_serial" {
    # require_serial: true (added for #205) makes pre-commit run actionlint as
    # a single process over all matched files instead of sharding them across
    # concurrent processes. This confirms that serialising does not mask a
    # real finding when multiple workflow files are checked together.
    if ! command -v actionlint > /dev/null 2>&1; then
        skip "actionlint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/serial-multi-workflow-test)"
    printf '%s' "${ACTIONLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/workflows"
    printf 'name: Valid One\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "Hello One"\n' > "${T}/.github/workflows/valid-one.yml"
    printf 'name: Valid Two\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "Hello Two"\n' > "${T}/.github/workflows/valid-two.yml"
    printf "name: Broken\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo \"\${{ steps.undefined.outputs.value }}\"\n" > "${T}/.github/workflows/broken.yml"
    git -C "${T}" add .pre-commit-config.yaml ".github/workflows/valid-one.yml" ".github/workflows/valid-two.yml" ".github/workflows/broken.yml"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── composite-action-lint ─────────────────────────────────────────────────────

@test "broken composite action (run step missing shell) is rejected" {
    if ! command -v composite-action-lint > /dev/null 2>&1; then
        skip "composite-action-lint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-composite-action-test)"
    printf '%s' "${COMPOSITE_ACTION_LINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/actions/bad-action"
    printf 'name: "Bad Action"\ndescription: "Missing shell"\nruns:\n  using: composite\n  steps:\n    - run: echo "hello"\n' > "${T}/.github/actions/bad-action/action.yml"
    git -C "${T}" add .pre-commit-config.yaml ".github/actions/bad-action/action.yml"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid composite action (shell specified) passes" {
    if ! command -v composite-action-lint > /dev/null 2>&1; then
        skip "composite-action-lint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-composite-action-test)"
    printf '%s' "${COMPOSITE_ACTION_LINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/actions/good-action"
    printf 'name: "Good Action"\ndescription: "Valid composite action"\nruns:\n  using: composite\n  steps:\n    - run: echo "hello"\n      shell: bash\n' > "${T}/.github/actions/good-action/action.yml"
    git -C "${T}" add .pre-commit-config.yaml ".github/actions/good-action/action.yml"
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
