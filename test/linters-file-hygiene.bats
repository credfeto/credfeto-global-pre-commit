#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

CHECK_MERGE_CONFLICT_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-merge-conflict
        name: check for merge conflicts
        entry: check-merge-conflict --assume-in-merge
        language: system
        types: [text]
'

CHECK_CASE_CONFLICT_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-case-conflict
        name: check for case conflicts
        entry: check-case-conflict
        language: system
'

CHECK_ADDED_LARGE_FILES_CONFIG='repos:
  - repo: local
    hooks:
      - id: check-added-large-files
        name: check for added large files
        entry: check-added-large-files
        language: system
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

# ── check-case-conflict ───────────────────────────────────────────────────────

@test "files differing only in case are rejected by check-case-conflict" {
    if ! command -v check-case-conflict > /dev/null 2>&1; then
        skip "check-case-conflict not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/broken-case-conflict-test)"
    printf '%s' "${CHECK_CASE_CONFLICT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'upper case name\n' > "${T}/File.txt"
    printf 'lower case name\n' > "${T}/file.txt"
    git -C "${T}" add .pre-commit-config.yaml File.txt file.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "files with distinct names pass check-case-conflict" {
    if ! command -v check-case-conflict > /dev/null 2>&1; then
        skip "check-case-conflict not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/valid-case-conflict-test)"
    printf '%s' "${CHECK_CASE_CONFLICT_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'first file\n' > "${T}/alpha.txt"
    printf 'second file\n' > "${T}/beta.txt"
    git -C "${T}" add .pre-commit-config.yaml alpha.txt beta.txt
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── check-added-large-files ───────────────────────────────────────────────────

@test "file exceeding 500 KB size threshold is rejected by check-added-large-files" {
    if ! command -v check-added-large-files > /dev/null 2>&1; then
        skip "check-added-large-files not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/large-file-fail-test)"
    printf '%s' "${CHECK_ADDED_LARGE_FILES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    dd if=/dev/zero of="${T}/big.bin" bs=1024 count=600 2>/dev/null
    git -C "${T}" add .pre-commit-config.yaml big.bin
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "small file well under 500 KB passes check-added-large-files" {
    if ! command -v check-added-large-files > /dev/null 2>&1; then
        skip "check-added-large-files not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/large-file-pass-test)"
    printf '%s' "${CHECK_ADDED_LARGE_FILES_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'small file content\n' > "${T}/small.txt"
    git -C "${T}" add .pre-commit-config.yaml small.txt
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
