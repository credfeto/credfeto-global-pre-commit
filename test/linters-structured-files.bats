#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

DOTENV_CONFIG='repos:
  - repo: local
    hooks:
      - id: dotenv-linter
        name: dotenv-linter
        entry: dotenv-linter check
        language: system
        files: (^|/)\.env(\.[^/]+)?$
'

XMLLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: xmllint
        name: xmllint
        entry: xmllint
        args: [--noout]
        language: system
        types: [xml]
'

MARKDOWNLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: markdownlint
        name: markdownlint
        entry: markdownlint
        language: system
        types: [markdown]
        args: [--disable, MD013, --]
'

YAMLLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: yamllint
        name: yamllint
        entry: yamllint
        language: system
        types: [yaml]
'

CHECK_YAML_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-yaml
        name: check yaml
        entry: check-yaml
        language: system
        types: [yaml]
        args: [--allow-multiple-documents]
'

CHECK_XML_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-xml
        name: check xml
        entry: check-xml
        language: system
        types: [xml]
'

CHECK_JSON_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-json
        name: check json
        entry: check-json
        language: system
        types: [json]
'

CHECK_TOML_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-toml
        name: check toml
        entry: check-toml
        language: system
        types: [toml]
'

# ── dotenv-linter ─────────────────────────────────────────────────────────────

@test "broken .env.example (duplicate key) is rejected" {
    if ! command -v dotenv-linter > /dev/null 2>&1; then
        skip "dotenv-linter not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-env-test)"
    printf '%s' "${DOTENV_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'FOO=bar\nFOO=baz\n' > "${T}/.env.example"
    git -C "${T}" add .pre-commit-config.yaml .env.example
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid .env.example passes" {
    if ! command -v dotenv-linter > /dev/null 2>&1; then
        skip "dotenv-linter not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-env-test)"
    printf '%s' "${DOTENV_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'APP_ENV=production\nAPP_NAME=myapp\n' > "${T}/.env.example"
    git -C "${T}" add .pre-commit-config.yaml .env.example
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── xmllint ───────────────────────────────────────────────────────────────────

@test "malformed XML (unclosed tag) is rejected" {
    if ! command -v xmllint > /dev/null 2>&1; then
        skip "xmllint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-xml-test)"
    printf '%s' "${XMLLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '<root><child></root>\n' > "${T}/data.xml"
    git -C "${T}" add .pre-commit-config.yaml data.xml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "well-formed XML passes" {
    if ! command -v xmllint > /dev/null 2>&1; then
        skip "xmllint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-xml-test)"
    printf '%s' "${XMLLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '<root><child/></root>\n' > "${T}/data.xml"
    git -C "${T}" add .pre-commit-config.yaml data.xml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── markdownlint ──────────────────────────────────────────────────────────────

@test "Markdown file with bare URL (MD034) is rejected" {
    if ! command -v markdownlint > /dev/null 2>&1; then
        skip "markdownlint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-markdown-test)"
    printf '%s' "${MARKDOWNLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '# Test\n\nVisit http://example.com for details.\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid Markdown file passes markdownlint" {
    if ! command -v markdownlint > /dev/null 2>&1; then
        skip "markdownlint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-markdown-test)"
    printf '%s' "${MARKDOWNLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '# Test\n\nThis is a valid markdown file with no violations.\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-yaml ───────────────────────────────────────────────────────────────

@test "YAML file with syntax error (unclosed bracket) is rejected by check-yaml" {
    if ! command -v check-yaml > /dev/null 2>&1; then
        skip "check-yaml not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-yaml-check-yaml-test)"
    printf '%s' "${CHECK_YAML_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'key: [unclosed\n' > "${T}/bad.yaml"
    git -C "${T}" add .pre-commit-config.yaml bad.yaml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "syntactically valid YAML passes check-yaml" {
    if ! command -v check-yaml > /dev/null 2>&1; then
        skip "check-yaml not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-yaml-check-yaml-test)"
    printf '%s' "${CHECK_YAML_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' 'key: value' > "${T}/good.yaml"
    git -C "${T}" add .pre-commit-config.yaml good.yaml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── yamllint ──────────────────────────────────────────────────────────────────

@test "YAML file with trailing spaces is rejected by yamllint" {
    if ! command -v yamllint > /dev/null 2>&1; then
        skip "yamllint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-yaml-yamllint-test)"
    printf '%s' "${YAMLLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' 'key: value   ' > "${T}/bad.yaml"
    git -C "${T}" add .pre-commit-config.yaml bad.yaml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "style-compliant YAML passes yamllint" {
    if ! command -v yamllint > /dev/null 2>&1; then
        skip "yamllint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-yaml-yamllint-test)"
    printf '%s' "${YAMLLINT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' 'key: value' > "${T}/good.yaml"
    git -C "${T}" add .pre-commit-config.yaml good.yaml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-xml ─────────────────────────────────────────────────────────────────

@test "malformed XML (unclosed tag) is rejected by check-xml" {
    if ! command -v check-xml > /dev/null 2>&1; then
        skip "check-xml not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-xml-check-xml-test)"
    printf '%s' "${CHECK_XML_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '<root><child></root>\n' > "${T}/data.xml"
    git -C "${T}" add .pre-commit-config.yaml data.xml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "well-formed XML passes check-xml" {
    if ! command -v check-xml > /dev/null 2>&1; then
        skip "check-xml not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-xml-check-xml-test)"
    printf '%s' "${CHECK_XML_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '<root><child/></root>\n' > "${T}/data.xml"
    git -C "${T}" add .pre-commit-config.yaml data.xml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-json ────────────────────────────────────────────────────────────────

@test "JSON file with trailing comma is rejected by check-json" {
    if ! command -v check-json > /dev/null 2>&1; then
        skip "check-json not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-json-check-json-test)"
    printf '%s' "${CHECK_JSON_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '{"key": "value",}\n' > "${T}/bad.json"
    git -C "${T}" add .pre-commit-config.yaml bad.json
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "syntactically valid JSON passes check-json" {
    if ! command -v check-json > /dev/null 2>&1; then
        skip "check-json not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-json-check-json-test)"
    printf '%s' "${CHECK_JSON_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '{"key": "value"}\n' > "${T}/good.json"
    git -C "${T}" add .pre-commit-config.yaml good.json
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-toml ────────────────────────────────────────────────────────────────

@test "TOML file with invalid syntax (unclosed string) is rejected by check-toml" {
    if ! command -v check-toml > /dev/null 2>&1; then
        skip "check-toml not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-toml-check-toml-test)"
    printf '%s' "${CHECK_TOML_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'key = "unclosed\n' > "${T}/bad.toml"
    git -C "${T}" add .pre-commit-config.yaml bad.toml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "syntactically valid TOML passes check-toml" {
    if ! command -v check-toml > /dev/null 2>&1; then
        skip "check-toml not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-toml-check-toml-test)"
    printf '%s' "${CHECK_TOML_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '[package]\nname = "my-package"\nversion = "1.0.0"\n' > "${T}/good.toml"
    git -C "${T}" add .pre-commit-config.yaml good.toml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
