#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

HADOLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: hadolint
        name: hadolint
        entry: hadolint
        language: system
        files: (^|/)Dockerfile[^/]*$
        args: [--config, .github/linters/.hadolint.yaml]
'

CHECK_COMPOSE_VOLUMES_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-compose-volumes
        name: check-compose-volumes
        entry: check-compose-volumes
        language: system
        files: (^|/)(docker-)?compose(\.[^/]+)?\.ya?ml$
'

# ── hadolint ──────────────────────────────────────────────────────────────────

@test "Dockerfile with ADD instruction (DL3020) is rejected" {
    if ! command -v hadolint > /dev/null 2>&1; then
        skip "hadolint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-dockerfile-test)"
    printf '%s' "${HADOLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/linters"
    printf '%s\n' '--- # hadolint config' > "${T}/.github/linters/.hadolint.yaml"
    printf 'FROM ubuntu:22.04\nADD file.txt /app/\n' > "${T}/Dockerfile"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add .pre-commit-config.yaml Dockerfile file.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "Dockerfile with COPY instruction passes hadolint" {
    if ! command -v hadolint > /dev/null 2>&1; then
        skip "hadolint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/clean-dockerfile-test)"
    printf '%s' "${HADOLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/linters"
    printf '%s\n' '--- # hadolint config' > "${T}/.github/linters/.hadolint.yaml"
    printf 'FROM ubuntu:22.04\nCOPY file.txt /app/\n' > "${T}/Dockerfile"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add .pre-commit-config.yaml Dockerfile file.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-compose-volumes ────────────────────────────────────────────────────

@test "docker-compose.yml with :r volume mode typo is rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/compose-volume-typo-test)"
    printf '%s' "${CHECK_COMPOSE_VOLUMES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'services:\n  app:\n    image: alpine:3.20\n    volumes:\n      - ./data:/data:r\n' > "${T}/docker-compose.yml"
    git -C "${T}" add .pre-commit-config.yaml docker-compose.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "docker-compose.yml with :ro volume mode passes" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/compose-volume-ok-test)"
    printf '%s' "${CHECK_COMPOSE_VOLUMES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'services:\n  app:\n    image: alpine:3.20\n    volumes:\n      - ./data:/data:ro\n      - ./cache:/cache:rw\n      - myvol:/var/lib/data\n' > "${T}/docker-compose.yml"
    git -C "${T}" add .pre-commit-config.yaml docker-compose.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
