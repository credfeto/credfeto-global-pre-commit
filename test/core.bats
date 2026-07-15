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

@test "changing .ai-instructions in cs-template is rejected (issue #186: protected in all repos now)" {
    local T
    T="$(make_repo feature/template-only-cs-template-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# instructions\n' > "${T}/.ai-instructions"
    git -C "${T}" add .pre-commit-config.yaml .ai-instructions
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "changing .ai-instructions in funfair-treasury-reporting is rejected (issue #186: protected in all repos now)" {
    local T
    T="$(make_repo feature/template-only-treasury-test)"
    git -C "${T}" remote add origin "git@github.com:funfair-tech/funfair-treasury-reporting.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# instructions\n' > "${T}/.ai-instructions"
    git -C "${T}" add .pre-commit-config.yaml .ai-instructions
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "changing ai/global/ in funfair-treasury-reporting is rejected (issue #186: protected in all repos now)" {
    local T
    T="$(make_repo feature/template-only-treasury-global-test)"
    git -C "${T}" remote add origin "git@github.com:funfair-tech/funfair-treasury-reporting.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/ai/global"
    printf '# global\n' > "${T}/ai/global/test.md"
    git -C "${T}" add .pre-commit-config.yaml ai/global/test.md
    run_hook "${T}"
    [ "${status}" -eq 1 ]
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

@test "staging release.rule-settings.json in non-hooks repo is rejected" {
    local T
    T="$(make_repo feature/release-rule-settings-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/src"
    printf '{}\n' > "${T}/src/release.rule-settings.json"
    git -C "${T}" add .pre-commit-config.yaml src/release.rule-settings.json
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging pre-release.rule-settings.json in non-hooks repo is rejected" {
    local T
    T="$(make_repo feature/pre-release-rule-settings-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/src"
    printf '{}\n' > "${T}/src/pre-release.rule-settings.json"
    git -C "${T}" add .pre-commit-config.yaml src/pre-release.rule-settings.json
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

# ── issue #186: .globalconfig and friends, now protected in ALL repos ────────

@test "staging .globalconfig in non-hooks repo is rejected" {
    local T
    T="$(make_repo feature/globalconfig-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '<GlobalConfig></GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .pre-commit-config.yaml .globalconfig
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "modifying an already-committed .globalconfig in non-hooks repo is rejected (credfeto-database-source-generator#169 scenario)" {
    local T
    T="$(make_repo feature/globalconfig-modify-nonhooks-test)"
    # The baseline commit below must bypass the real hook (core.hooksPath) --
    # with this fix in place a .globalconfig could never be committed through
    # it in the first place, but the point of this test is what happens when
    # one is *already* tracked (e.g. from before this fix existed) and gets
    # modified in place, as in credfeto-database-source-generator#169.
    mkdir -p "${T}/.no-hooks"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '<GlobalConfig>\n  <NoWarn>FFS0040=suggestion</NoWarn>\n</GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .pre-commit-config.yaml .globalconfig
    git -C "${T}" commit --quiet -m baseline
    printf '<GlobalConfig>\n  <NoWarn>FFS0040=error</NoWarn>\n</GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .globalconfig
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging a nested .globalconfig in non-hooks repo is rejected" {
    local T
    T="$(make_repo feature/globalconfig-nested-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/src"
    printf '<GlobalConfig></GlobalConfig>\n' > "${T}/src/.globalconfig"
    git -C "${T}" add .pre-commit-config.yaml src/.globalconfig
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging .globalconfig in hooks repo is still rejected" {
    local T
    T="$(make_repo feature/globalconfig-hooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '<GlobalConfig></GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .pre-commit-config.yaml .globalconfig
    run_hook_as_hooks_repo "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging global.json in non-hooks repo is now rejected" {
    local T
    T="$(make_repo feature/globaljson-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '{"sdk":{"version":"8.0.0"}}\n' > "${T}/global.json"
    git -C "${T}" add .pre-commit-config.yaml global.json
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging .sqlfluff in non-hooks repo is now rejected" {
    local T
    T="$(make_repo feature/sqlfluff-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '[sqlfluff]\ndialect = tsql\n' > "${T}/.sqlfluff"
    git -C "${T}" add .pre-commit-config.yaml .sqlfluff
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging .tsqllintrc in non-hooks repo is now rejected" {
    local T
    T="$(make_repo feature/tsqllintrc-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '{}\n' > "${T}/.tsqllintrc"
    git -C "${T}" add .pre-commit-config.yaml .tsqllintrc
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging Directory.Build.props in non-hooks repo is now rejected" {
    local T
    T="$(make_repo feature/directory-build-props-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '<Project></Project>\n' > "${T}/Directory.Build.props"
    git -C "${T}" add .pre-commit-config.yaml Directory.Build.props
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging a file under .github/linters/ in non-hooks repo is now rejected" {
    local T
    T="$(make_repo feature/github-linters-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/.github/linters"
    printf 'rules: {}\n' > "${T}/.github/linters/.yamllint.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/linters/.yamllint.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging a dotfile matching the broad lint wildcard in non-hooks repo is now rejected" {
    local T
    T="$(make_repo feature/broad-lint-wildcard-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'rules: {}\n' > "${T}/.foolint"
    git -C "${T}" add .pre-commit-config.yaml .foolint
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

@test "staging global.json in hooks repo is still rejected" {
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

@test "staging ai/local/*.md in non-hooks repo passes (issue #186: the AI-memory workflow must keep working everywhere)" {
    local T
    T="$(make_repo feature/ai-local-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/ai/local"
    printf '# local notes\n' > "${T}/ai/local/notes.instructions.md"
    git -C "${T}" add .pre-commit-config.yaml ai/local/notes.instructions.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "staging ai/local/*.md in hooks repo is rejected" {
    local T
    T="$(make_repo feature/ai-local-hooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/ai/local"
    printf '# local notes\n' > "${T}/ai/local/notes.instructions.md"
    git -C "${T}" add .pre-commit-config.yaml ai/local/notes.instructions.md
    run_hook_as_hooks_repo "${T}"
    [ "${status}" -eq 1 ]
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
