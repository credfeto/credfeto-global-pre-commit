#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

PYLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: pylint
        name: pylint
        entry: pylint
        language: system
        types: [python]
'

FLAKE8_CONFIG='repos:
  - repo: local
    hooks:
      - id: flake8
        name: flake8
        entry: flake8
        language: system
        types: [python]
'

# ── pylint ────────────────────────────────────────────────────────────────────

@test "Python file with undefined variable (E0602) is rejected" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-py-test)"
    printf '%s' "${PYLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'def bad():\n    print(undefined_var)\n' > "${T}/bad.py"
    git -C "${T}" add .pre-commit-config.yaml bad.py
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean Python file passes pylint" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-py-test)"
    printf '%s' "${PYLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '"""A valid module."""\n\n\ndef greet(name):\n    """Return a greeting."""\n    return f"Hello, {name}"\n' > "${T}/good.py"
    git -C "${T}" add .pre-commit-config.yaml good.py
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── flake8 ────────────────────────────────────────────────────────────────────

@test "Python file with unused import (F401) is rejected by flake8" {
    if ! command -v flake8 > /dev/null 2>&1; then
        skip "flake8 not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-py-flake8-test)"
    printf '%s' "${FLAKE8_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'import os\n\n\ndef greet(name):\n    return f"Hello, {name}"\n' > "${T}/bad.py"
    git -C "${T}" add .pre-commit-config.yaml bad.py
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean Python file passes flake8" {
    if ! command -v flake8 > /dev/null 2>&1; then
        skip "flake8 not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-py-flake8-test)"
    printf '%s' "${FLAKE8_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'def greet(name):\n    return f"Hello, {name}"\n' > "${T}/good.py"
    git -C "${T}" add .pre-commit-config.yaml good.py
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
