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

# ── template-only file protection ────────────────────────────────────────────

@test "changing .ai-instructions in a non-template repo is rejected" {
    local T
    T="$(make_repo feature/template-only-ai-instructions-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# instructions\n' > "${T}/.ai-instructions"
    git -C "${T}" add .pre-commit-config.yaml .ai-instructions
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "changing ai/global/ in a non-template repo is rejected" {
    local T
    T="$(make_repo feature/template-only-ai-global-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/ai/global"
    printf '# global\n' > "${T}/ai/global/test.md"
    git -C "${T}" add .pre-commit-config.yaml ai/global/test.md
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "changing .ai-instructions in cs-template is allowed" {
    local T
    T="$(make_repo feature/template-only-cs-template-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# instructions\n' > "${T}/.ai-instructions"
    git -C "${T}" add .pre-commit-config.yaml .ai-instructions
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "changing .ai-instructions in funfair-treasury-reporting is allowed" {
    local T
    T="$(make_repo feature/template-only-treasury-test)"
    git -C "${T}" remote add origin "git@github.com:funfair-tech/funfair-treasury-reporting.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# instructions\n' > "${T}/.ai-instructions"
    git -C "${T}" add .pre-commit-config.yaml .ai-instructions
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "changing ai/global/ in funfair-treasury-reporting is allowed" {
    local T
    T="$(make_repo feature/template-only-treasury-global-test)"
    git -C "${T}" remote add origin "git@github.com:funfair-tech/funfair-treasury-reporting.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/ai/global"
    printf '# global\n' > "${T}/ai/global/test.md"
    git -C "${T}" add .pre-commit-config.yaml ai/global/test.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── linter/style config protection (all repos) ───────────────────────────────

@test "staging .shellcheckrc in non-hooks repo is rejected" {
    local T
    T="$(make_repo feature/shellcheckrc-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'check-sourced=false\n' > "${T}/.shellcheckrc"
    git -C "${T}" add .pre-commit-config.yaml .shellcheckrc
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── hooks-repo protected file guard ──────────────────────────────────────────

@test "staging .shellcheckrc in hooks repo is rejected" {
    local T
    T="$(make_repo feature/shellcheckrc-protection-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'check-sourced=false\n' > "${T}/.shellcheckrc"
    git -C "${T}" add .pre-commit-config.yaml .shellcheckrc
    run_hook_as_hooks_repo "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging global.json in hooks repo is rejected by hooks-repo guard" {
    local T
    T="$(make_repo feature/hooks-repo-globaljson-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '{"sdk":{"version":"8.0.0"}}\n' > "${T}/global.json"
    git -C "${T}" add .pre-commit-config.yaml global.json
    run_hook_as_hooks_repo "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging non-protected file in hooks repo passes" {
    local T
    T="$(make_repo feature/hooks-repo-non-protected-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# Test\n' > "${T}/README.md"
    git -C "${T}" add .pre-commit-config.yaml README.md
    run_hook_as_hooks_repo "${T}"
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
