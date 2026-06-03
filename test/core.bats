#!/usr/bin/env bats
# Core pre-commit hook acceptance tests:
# branch protection, merge-commit guard, ignored-file guard, dotnet-tools.json guard.

load test_helper

# ── nothing staged ────────────────────────────────────────────────────────────

@test "nothing staged exits non-zero" {
    local T
    T="$(make_repo)"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── branch protection ─────────────────────────────────────────────────────────

@test "commit on main branch is rejected" {
    local T
    T="$(make_repo main)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "commit on master branch is rejected" {
    local T
    T="$(make_repo master)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── merge commit guard ────────────────────────────────────────────────────────

@test "merge commit is rejected" {
    local T
    T="$(make_repo feature/merge-test)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    printf 'deadbeef1234\n' > "${T}/.git/MERGE_HEAD"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── ignored file guard ────────────────────────────────────────────────────────

@test "ignored tracked file is rejected" {
    local T
    T="$(make_repo feature/ignored-file-test)"
    printf '*.secret\n' > "${T}/.gitignore"
    printf 'password=hunter2\n' > "${T}/config.secret"
    git -C "${T}" add .gitignore
    git -C "${T}" add -f config.secret
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── dotnet-tools.json guard ───────────────────────────────────────────────────

@test "dotnet-tools.json anywhere in repo is rejected" {
    local T
    T="$(make_repo feature/dotnet-tools-json-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    mkdir -p "${T}/.config"
    printf '{}\n' > "${T}/.config/dotnet-tools.json"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "clean commit without dotnet-tools.json passes" {
    local T
    T="$(make_repo feature/no-dotnet-tools-json-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── clean commit ──────────────────────────────────────────────────────────────

@test "clean commit on feature branch passes" {
    local T
    T="$(make_repo feature/clean-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# Test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
