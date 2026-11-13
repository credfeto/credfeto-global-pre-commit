#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

# ── eslint ────────────────────────────────────────────────────────────────────

@test "JavaScript with unused variable is rejected" {
    if ! command -v eslint > /dev/null 2>&1; then
        skip "eslint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T ESLINT_CONFIG
    T="$(make_repo feature/broken-js-test)"
    ESLINT_CONFIG="repos:
  - repo: local
    hooks:
      - id: eslint
        name: eslint
        entry: ${REPO_DIR}/src/scripts/run-eslint
        language: system
        files: \\.(ts|tsx|js|jsx)\$
"
    printf '%s' "${ESLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'module.exports = [{ rules: { "no-unused-vars": "error" } }];\n' > "${T}/eslint.config.cjs"
    printf '{"scripts":{"test":"true"}}' > "${T}/package.json"
    printf 'var unused = 1;\n' > "${T}/bad.js"
    git -C "${T}" add .pre-commit-config.yaml bad.js
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean JavaScript passes" {
    if ! command -v eslint > /dev/null 2>&1; then
        skip "eslint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T ESLINT_CONFIG
    T="$(make_repo feature/valid-js-test)"
    ESLINT_CONFIG="repos:
  - repo: local
    hooks:
      - id: eslint
        name: eslint
        entry: ${REPO_DIR}/src/scripts/run-eslint
        language: system
        files: \\.(ts|tsx|js|jsx)\$
"
    printf '%s' "${ESLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'module.exports = [{ rules: { "no-unused-vars": "error" } }];\n' > "${T}/eslint.config.cjs"
    printf '{"scripts":{"test":"true"}}' > "${T}/package.json"
    printf 'var x = 1;\nconsole.log(x);\n' > "${T}/clean.js"
    git -C "${T}" add .pre-commit-config.yaml clean.js
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── stylelint ─────────────────────────────────────────────────────────────────

@test "CSS with empty block is rejected" {
    if ! command -v stylelint > /dev/null 2>&1; then
        skip "stylelint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T STYLELINT_CONFIG
    T="$(make_repo feature/broken-css-test)"
    STYLELINT_CONFIG="repos:
  - repo: local
    hooks:
      - id: stylelint
        name: stylelint
        entry: ${REPO_DIR}/src/scripts/run-stylelint
        language: system
        files: \\.css\$
"
    printf '%s' "${STYLELINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '{"rules":{"block-no-empty":true}}\n' > "${T}/.stylelintrc.json"
    printf '{"scripts":{"test":"true"}}\n' > "${T}/package.json"
    printf 'a {}\n' > "${T}/bad.css"
    git -C "${T}" add .pre-commit-config.yaml package.json bad.css
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid CSS passes" {
    if ! command -v stylelint > /dev/null 2>&1; then
        skip "stylelint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T STYLELINT_CONFIG
    T="$(make_repo feature/valid-css-test)"
    STYLELINT_CONFIG="repos:
  - repo: local
    hooks:
      - id: stylelint
        name: stylelint
        entry: ${REPO_DIR}/src/scripts/run-stylelint
        language: system
        files: \\.css\$
"
    printf '%s' "${STYLELINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '{"rules":{"block-no-empty":true}}\n' > "${T}/.stylelintrc.json"
    printf '{"scripts":{"test":"true"}}\n' > "${T}/package.json"
    printf 'a { color: red; }\n' > "${T}/clean.css"
    git -C "${T}" add .pre-commit-config.yaml package.json clean.css
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
