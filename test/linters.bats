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

ACTIONLINT_CONFIG='repos:
  - repo: local
    hooks:
      - id: actionlint
        name: actionlint
        entry: actionlint
        language: system
        files: ^\.github/workflows/.*\.(yml|yaml)$
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

CHECK_MERGE_CONFLICT_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-merge-conflict
        name: check for merge conflicts
        entry: check-merge-conflict
        language: system
        types: [text]
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

CHECK_SHEBANG_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-shebang-scripts-are-executable
        name: check that scripts with shebangs are executable
        entry: check-shebang-scripts-are-executable
        language: system
        types: [text]
'

CHECK_EXECUTABLES_HAVE_SHEBANGS_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-executables-have-shebangs
        name: check that executables have shebangs
        entry: check-executables-have-shebangs
        language: system
        types: [text, executable]
'

DETECT_PRIVATE_KEY_CONFIG='repos:
  - repo: local
    hooks:
      - id: detect-private-key
        name: detect private key
        entry: detect-private-key
        language: system
        types: [text]
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

TRAILING_WHITESPACE_CONFIG='repos:
  - repo: local
    hooks:
      - id: trailing-whitespace
        name: trim trailing whitespace
        entry: trailing-whitespace-fixer
        language: system
        types: [text]
'

MIXED_LINE_ENDING_CONFIG='repos:
  - repo: local
    hooks:
      - id: mixed-line-ending
        name: mixed line ending
        entry: mixed-line-ending
        language: system
        types: [text]
'

END_OF_FILE_FIXER_CONFIG='repos:
  - repo: local
    hooks:
      - id: end-of-file-fixer
        name: fix end of files
        entry: end-of-file-fixer
        language: system
        types: [text]
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

# ── PSScriptAnalyzer ──────────────────────────────────────────────────────────

@test "broken PowerShell script (PSAvoidUsingWriteHost) is rejected" {
    if ! command -v pwsh > /dev/null 2>&1; then
        skip "pwsh not installed"
    fi
    if ! pwsh -NoProfile -NonInteractive -Command "Import-Module PSScriptAnalyzer -ErrorAction Stop; exit 0" > /dev/null 2>&1; then
        skip "PSScriptAnalyzer module not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T PSSCRIPTANALYZER_CONFIG
    T="$(make_repo feature/broken-ps1-test)"
    PSSCRIPTANALYZER_CONFIG="repos:
  - repo: local
    hooks:
      - id: run-psscriptanalyzer
        name: run-psscriptanalyzer
        entry: ${REPO_DIR}/src/scripts/run-psscriptanalyzer
        language: system
        files: \\.(ps1|psm1|psd1)\$
"
    printf '%s' "${PSSCRIPTANALYZER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'Write-Host "hello"\n' > "${T}/test.ps1"
    git -C "${T}" add .pre-commit-config.yaml test.ps1
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean PowerShell script passes" {
    if ! command -v pwsh > /dev/null 2>&1; then
        skip "pwsh not installed"
    fi
    if ! pwsh -NoProfile -NonInteractive -Command "Import-Module PSScriptAnalyzer -ErrorAction Stop; exit 0" > /dev/null 2>&1; then
        skip "PSScriptAnalyzer module not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T PSSCRIPTANALYZER_CONFIG
    T="$(make_repo feature/clean-ps1-test)"
    PSSCRIPTANALYZER_CONFIG="repos:
  - repo: local
    hooks:
      - id: run-psscriptanalyzer
        name: run-psscriptanalyzer
        entry: ${REPO_DIR}/src/scripts/run-psscriptanalyzer
        language: system
        files: \\.(ps1|psm1|psd1)\$
"
    printf '%s' "${PSSCRIPTANALYZER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf 'function Get-Greeting {\n    param ([string]$Name)\n    Write-Output "Hello, $Name"\n}\n' > "${T}/test.ps1"
    git -C "${T}" add .pre-commit-config.yaml test.ps1
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

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
    git -C "${T}" add .pre-commit-config.yaml .stylelintrc.json package.json bad.css
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
    git -C "${T}" add .pre-commit-config.yaml .stylelintrc.json package.json clean.css
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── ansible-lint ──────────────────────────────────────────────────────────────

_ansible_env_ok() {
    local _probe_dir _probe_out
    _probe_dir="$(mktemp -d)"
    _probe_out="$(ansible-lint --nocolor "${_probe_dir}" 2>&1 || true)"
    rm -rf "${_probe_dir}"
    if printf '%s' "${_probe_out}" | grep -qi "do not match\|broken execution"; then
        return 1
    fi
    return 0
}

@test "broken Ansible playbook (yaml[truthy] violation) is rejected" {
    if ! command -v ansible-lint > /dev/null 2>&1; then
        skip "ansible-lint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! _ansible_env_ok; then
        skip "ansible-lint environment broken (version mismatch)"
    fi
    local T
    T="$(make_repo feature/broken-playbook-test)"
    printf 'repos:\n  - repo: local\n    hooks:\n      - id: ansible-lint\n        name: ansible-lint\n        entry: ansible-lint -v --force-color --exclude .github\n        language: system\n        pass_filenames: false\n        always_run: true\n' > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' '- name: Broken playbook' '  hosts: localhost' '  gather_facts: yes' '  tasks:' '    - name: Hello world' '      ansible.builtin.debug:' '        msg: Hello' > "${T}/broken.yml"
    git -C "${T}" add .pre-commit-config.yaml broken.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid Ansible playbook passes" {
    if ! command -v ansible-lint > /dev/null 2>&1; then
        skip "ansible-lint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! _ansible_env_ok; then
        skip "ansible-lint environment broken (version mismatch)"
    fi
    local T
    T="$(make_repo feature/valid-playbook-test)"
    printf 'repos:\n  - repo: local\n    hooks:\n      - id: ansible-lint\n        name: ansible-lint\n        entry: ansible-lint -v --force-color --exclude .github\n        language: system\n        pass_filenames: false\n        always_run: true\n' > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' '- name: Valid test playbook' '  hosts: all' '  gather_facts: false' '  tasks:' '    - name: Print hello' '      ansible.builtin.debug:' '        msg: Hello World' > "${T}/clean.yml"
    git -C "${T}" add .pre-commit-config.yaml clean.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
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
    git -C "${T}" add .pre-commit-config.yaml .github/linters/.hadolint.yaml Dockerfile file.txt
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
    git -C "${T}" add .pre-commit-config.yaml .github/linters/.hadolint.yaml Dockerfile file.txt
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

# ── check-shebang-scripts-are-executable ─────────────────────────────────────

@test "non-executable file with shebang is rejected by check-shebang-scripts-are-executable" {
    if ! command -v check-shebang-scripts-are-executable > /dev/null 2>&1; then
        skip "check-shebang-scripts-are-executable not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/non-executable-shebang-test)"
    printf '%s' "${CHECK_SHEBANG_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '#!/bin/sh\necho hello\n' > "${T}/test.sh"
    git -C "${T}" add .pre-commit-config.yaml test.sh
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "executable file with shebang passes check-shebang-scripts-are-executable" {
    if ! command -v check-shebang-scripts-are-executable > /dev/null 2>&1; then
        skip "check-shebang-scripts-are-executable not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/executable-shebang-test)"
    printf '%s' "${CHECK_SHEBANG_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '#!/bin/sh\necho hello\n' > "${T}/test.sh"
    chmod +x "${T}/test.sh"
    git -C "${T}" add .pre-commit-config.yaml test.sh
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-executables-have-shebangs ──────────────────────────────────────────

@test "executable file without shebang is rejected by check-executables-have-shebangs" {
    if ! command -v check-executables-have-shebangs > /dev/null 2>&1; then
        skip "check-executables-have-shebangs not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/executable-no-shebang-test)"
    printf '%s' "${CHECK_EXECUTABLES_HAVE_SHEBANGS_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'echo hello\n' > "${T}/run.sh"
    chmod +x "${T}/run.sh"
    git -C "${T}" add .pre-commit-config.yaml run.sh
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "executable file with shebang passes check-executables-have-shebangs" {
    if ! command -v check-executables-have-shebangs > /dev/null 2>&1; then
        skip "check-executables-have-shebangs not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/executable-with-shebang-test)"
    printf '%s' "${CHECK_EXECUTABLES_HAVE_SHEBANGS_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '#!/bin/sh\necho hello\n' > "${T}/run.sh"
    chmod +x "${T}/run.sh"
    git -C "${T}" add .pre-commit-config.yaml run.sh
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

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

# ── trailing-whitespace ───────────────────────────────────────────────────────

@test "text file with trailing spaces is rejected by trailing-whitespace" {
    if ! command -v trailing-whitespace-fixer > /dev/null 2>&1; then
        skip "trailing-whitespace-fixer not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-trailing-whitespace-test)"
    printf '%s' "${TRAILING_WHITESPACE_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'hello   \nworld\n' > "${T}/bad.txt"
    git -C "${T}" add .pre-commit-config.yaml bad.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "text file with no trailing whitespace passes trailing-whitespace" {
    if ! command -v trailing-whitespace-fixer > /dev/null 2>&1; then
        skip "trailing-whitespace-fixer not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-trailing-whitespace-test)"
    printf '%s' "${TRAILING_WHITESPACE_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'hello\nworld\n' > "${T}/clean.txt"
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

# ── mixed-line-ending ─────────────────────────────────────────────────────────

@test "file with mixed CRLF and LF line endings is rejected by mixed-line-ending" {
    if ! command -v mixed-line-ending > /dev/null 2>&1; then
        skip "mixed-line-ending not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-mixed-line-ending-test)"
    printf '%s' "${MIXED_LINE_ENDING_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'first line\r\nsecond line\n' > "${T}/bad.txt"
    git -C "${T}" add .pre-commit-config.yaml bad.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "file with consistent LF-only line endings passes mixed-line-ending" {
    if ! command -v mixed-line-ending > /dev/null 2>&1; then
        skip "mixed-line-ending not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-mixed-line-ending-test)"
    printf '%s' "${MIXED_LINE_ENDING_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'first line\nsecond line\n' > "${T}/clean.txt"
    git -C "${T}" add .pre-commit-config.yaml clean.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-merge-conflict ──────────────────────────────────────────────────────

@test "text file with merge conflict markers is rejected by check-merge-conflict" {
    if ! command -v check-merge-conflict > /dev/null 2>&1; then
        skip "check-merge-conflict not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-merge-conflict-test)"
    printf '%s' "${CHECK_MERGE_CONFLICT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '<<<<<<< HEAD\nsome change\n=======\nother change\n>>>>>>> feature-branch\n' > "${T}/conflict.txt"
    git -C "${T}" add .pre-commit-config.yaml conflict.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean text file passes check-merge-conflict" {
    if ! command -v check-merge-conflict > /dev/null 2>&1; then
        skip "check-merge-conflict not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-merge-conflict-test)"
    printf '%s' "${CHECK_MERGE_CONFLICT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'This file has no merge conflict markers.\n' > "${T}/clean.txt"
    git -C "${T}" add .pre-commit-config.yaml clean.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── end-of-file-fixer ─────────────────────────────────────────────────────────

@test "text file missing trailing newline is rejected by end-of-file-fixer" {
    if ! command -v end-of-file-fixer > /dev/null 2>&1; then
        skip "end-of-file-fixer not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-eof-test)"
    printf '%s' "${END_OF_FILE_FIXER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'no newline at end' > "${T}/bad.txt"
    git -C "${T}" add .pre-commit-config.yaml bad.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "text file with trailing newline passes end-of-file-fixer" {
    if ! command -v end-of-file-fixer > /dev/null 2>&1; then
        skip "end-of-file-fixer not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-eof-test)"
    printf '%s' "${END_OF_FILE_FIXER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'content with trailing newline\n' > "${T}/clean.txt"
    git -C "${T}" add .pre-commit-config.yaml clean.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
