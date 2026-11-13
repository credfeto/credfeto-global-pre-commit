#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

DETECT_PRIVATE_KEY_CONFIG='repos:
  - repo: local
    hooks:
      - id: detect-private-key
        name: detect private key
        entry: detect-private-key
        language: system
        types: [text]
        exclude: ^certs/([^/]*\.local|localhost)\.(pem|key)$
'

TRUFFLEHOG_CONFIG='repos:
  - repo: local
    hooks:
      - id: trufflehog
        name: TruffleHog
        description: Detect secrets in your data with TruffleHog.
        entry: trufflehog git file://. --since-commit HEAD --fail --no-update --no-verification --trust-local-git-config
        language: system
        pass_filenames: false
'

# ── trufflehog ────────────────────────────────────────────────────────────────

@test "staged RSA private key is rejected by trufflehog" {
    if ! command -v trufflehog > /dev/null 2>&1; then
        skip "trufflehog not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! command -v openssl > /dev/null 2>&1; then
        skip "openssl not installed"
    fi
    local T
    T="$(make_repo feature/trufflehog-secret-test)"
    # Establish HEAD with an initial commit using an empty pre-commit config.
    # Trufflehog requires at least one prior commit for --since-commit HEAD to
    # resolve; the empty config avoids running the global linters on fixture files.
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'placeholder\n' > "${T}/placeholder.txt"
    git -C "${T}" add .pre-commit-config.yaml placeholder.txt
    git -C "${T}" commit --quiet -m "chore: initial placeholder"
    # Replace with the scoped trufflehog config and stage a generated RSA key.
    printf '%s' "${TRUFFLEHOG_CONFIG}" > "${T}/.pre-commit-config.yaml"
    openssl genrsa 512 2>/dev/null > "${T}/test-key.pem"
    git -C "${T}" add .pre-commit-config.yaml test-key.pem
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staged file with no secrets passes trufflehog" {
    if ! command -v trufflehog > /dev/null 2>&1; then
        skip "trufflehog not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/trufflehog-clean-test)"
    # Establish HEAD with an initial commit using an empty pre-commit config.
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'placeholder\n' > "${T}/placeholder.txt"
    git -C "${T}" add .pre-commit-config.yaml placeholder.txt
    git -C "${T}" commit --quiet -m "chore: initial placeholder"
    # Replace with the scoped trufflehog config and stage a clean text file.
    printf '%s' "${TRUFFLEHOG_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'This file contains no secrets or credentials.\n' > "${T}/clean.txt"
    git -C "${T}" add .pre-commit-config.yaml clean.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── detect-private-key ────────────────────────────────────────────────────────

@test "file containing PEM private key header is rejected by detect-private-key" {
    if ! command -v detect-private-key > /dev/null 2>&1; then
        skip "detect-private-key not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! command -v openssl > /dev/null 2>&1; then
        skip "openssl not installed"
    fi
    local T
    T="$(make_repo feature/detect-private-key-fail-test)"
    printf '%s' "${DETECT_PRIVATE_KEY_CONFIG}" > "${T}/.pre-commit-config.yaml"
    openssl genrsa 512 2>/dev/null > "${T}/secret.pem"
    git -C "${T}" add .pre-commit-config.yaml secret.pem
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "file with no private key content passes detect-private-key" {
    if ! command -v detect-private-key > /dev/null 2>&1; then
        skip "detect-private-key not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/detect-private-key-pass-test)"
    printf '%s' "${DETECT_PRIVATE_KEY_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'This file contains no private key or sensitive credentials.\n' > "${T}/clean.txt"
    git -C "${T}" add .pre-commit-config.yaml clean.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "PEM private key under certs/ matching *.local naming is excluded from detect-private-key" {
    if ! command -v detect-private-key > /dev/null 2>&1; then
        skip "detect-private-key not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! command -v openssl > /dev/null 2>&1; then
        skip "openssl not installed"
    fi
    local T
    T="$(make_repo feature/detect-private-key-certs-exclude-test)"
    printf '%s' "${DETECT_PRIVATE_KEY_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/certs"
    openssl genrsa 512 2>/dev/null > "${T}/certs/localhost.key"
    openssl genrsa 512 2>/dev/null > "${T}/certs/npm.local.pem"
    git -C "${T}" add .pre-commit-config.yaml certs/localhost.key certs/npm.local.pem
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "PEM private key under certs/ not matching *.local naming is still rejected by detect-private-key" {
    if ! command -v detect-private-key > /dev/null 2>&1; then
        skip "detect-private-key not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! command -v openssl > /dev/null 2>&1; then
        skip "openssl not installed"
    fi
    local T
    T="$(make_repo feature/detect-private-key-certs-not-excluded-test)"
    printf '%s' "${DETECT_PRIVATE_KEY_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/certs"
    openssl genrsa 512 2>/dev/null > "${T}/certs/production.key"
    git -C "${T}" add .pre-commit-config.yaml certs/production.key
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}
