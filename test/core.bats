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

@test "changing ai/global/ in cs-template is allowed (whitelisted: it's the canonical source)" {
    local T
    T="$(make_repo feature/ai-global-cs-template-whitelist-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/ai/global"
    printf '# global\n' > "${T}/ai/global/test.md"
    git -C "${T}" add .pre-commit-config.yaml ai/global/test.md
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "changing .ai-instructions in cs-template is allowed (whitelisted: it's the canonical source)" {
    local T
    T="$(make_repo feature/ai-instructions-cs-template-whitelist-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '# instructions\n' > "${T}/.ai-instructions"
    git -C "${T}" add .pre-commit-config.yaml .ai-instructions
    run_hook "${T}"
    [ "${status}" -eq 0 ]
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

@test "staging an unrelated dotfile that merely contains lint in its name passes (no broad wildcard, explicit names only)" {
    local T
    T="$(make_repo feature/unrelated-lint-named-file-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'rules: {}\n' > "${T}/.foolint"
    git -C "${T}" add .pre-commit-config.yaml .foolint
    run_hook "${T}"
    [ "${status}" -eq 0 ]
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

@test "staging root .gitignore in non-hooks repo is rejected (issue #186 follow-up)" {
    local T
    T="$(make_repo feature/root-gitignore-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'bin/\nobj/\n' > "${T}/.gitignore"
    git -C "${T}" add .pre-commit-config.yaml .gitignore
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging a nested .gitignore in non-hooks repo passes (root-only)" {
    local T
    T="$(make_repo feature/nested-gitignore-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/src"
    printf 'bin/\nobj/\n' > "${T}/src/.gitignore"
    git -C "${T}" add .pre-commit-config.yaml src/.gitignore
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "staging root .gitignore in cs-template is also rejected (no template exemption; unlike .ai-instructions/ai/global, it has no cs-template-authored canonical copy to protect)" {
    local T
    T="$(make_repo feature/root-gitignore-cs-template-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'bin/\nobj/\n' > "${T}/.gitignore"
    git -C "${T}" add .pre-commit-config.yaml .gitignore
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging root .gitignore in hooks repo is rejected" {
    local T
    T="$(make_repo feature/root-gitignore-hooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'bin/\nobj/\n' > "${T}/.gitignore"
    git -C "${T}" add .pre-commit-config.yaml .gitignore
    run_hook_as_hooks_repo "${T}"
    [ "${status}" -eq 1 ]
}

# ── maintain-in-repo ownership (workflow/action files) ───────────────────────

@test "editing a workflow file maintained in this repo is allowed" {
    local T
    T="$(make_repo feature/maintain-own-workflow-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/example-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/.github/workflows"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\n# Maintain in repo: example-repo\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    git -C "${T}" commit --quiet -m baseline
    printf -- '---\n# Maintain in repo: example-repo\nname: test\non: push\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "editing a workflow file maintained in a different repo is rejected" {
    local T
    T="$(make_repo feature/maintain-other-workflow-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/attacker-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/.github/workflows"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\n# Maintain in repo: owner-repo\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    git -C "${T}" commit --quiet -m baseline
    printf -- '---\n# Maintain in repo: owner-repo\nname: test\non: push\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "rewriting the ownership comment to self-authorise in the same commit is still rejected" {
    local T
    T="$(make_repo feature/maintain-rewrite-attack-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/attacker-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/.github/workflows"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\n# Maintain in repo: owner-repo\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    git -C "${T}" commit --quiet -m baseline
    # Attempt to claim ownership by rewriting the comment in the same diff --
    # the check must still consult HEAD's (unmodified) declared owner.
    printf -- '---\n# Maintain in repo: attacker-repo\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "editing an action.yml maintained in a different repo is rejected" {
    local T
    T="$(make_repo feature/maintain-other-action-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/attacker-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/.github/actions/some-action"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\n# Maintain in repo: owner-repo\nname: test\n' > "${T}/.github/actions/some-action/action.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/actions/some-action/action.yml
    git -C "${T}" commit --quiet -m baseline
    printf -- '---\n# Maintain in repo: owner-repo\nname: test v2\n' > "${T}/.github/actions/some-action/action.yml"
    git -C "${T}" add .github/actions/some-action/action.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "deleting a workflow file maintained in a different repo is rejected" {
    local T
    T="$(make_repo feature/maintain-delete-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/attacker-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/.github/workflows"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\n# Maintain in repo: owner-repo\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    git -C "${T}" commit --quiet -m baseline
    git -C "${T}" rm --quiet .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "editing a workflow file with no ownership comment is allowed from any repo" {
    local T
    T="$(make_repo feature/maintain-no-marker-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/some-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/.github/workflows"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    git -C "${T}" commit --quiet -m baseline
    printf -- '---\nname: test\non: push\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "adding a new workflow file in a template repo without self-declaring ownership is rejected" {
    local T
    T="$(make_repo feature/maintain-new-file-template-no-marker-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/example-server-template.git"
    mkdir -p "${T}/.github/workflows"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "adding a new workflow file in a template repo that self-declares ownership is allowed" {
    local T
    T="$(make_repo feature/maintain-new-file-template-marker-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/example-server-template.git"
    mkdir -p "${T}/.github/workflows"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\n# Maintain in repo: example-server-template\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "adding a new workflow file in a non-template repo requires no ownership marker" {
    local T
    T="$(make_repo feature/maintain-new-file-nontemplate-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/some-service.git"
    mkdir -p "${T}/.github/workflows"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '---\nname: test\n' > "${T}/.github/workflows/test.yml"
    git -C "${T}" add .pre-commit-config.yaml .github/workflows/test.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "a file outside .github/workflows and .github/actions with a maintain comment is not checked" {
    local T
    T="$(make_repo feature/maintain-unrelated-file-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/attacker-repo.git"
    mkdir -p "${T}/.no-hooks" "${T}/config"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '# Maintain in repo: owner-repo\nkey: value\n' > "${T}/config/settings.yml"
    git -C "${T}" add .pre-commit-config.yaml config/settings.yml
    git -C "${T}" commit --quiet -m baseline
    printf -- '# Maintain in repo: owner-repo\nkey: changed\n' > "${T}/config/settings.yml"
    git -C "${T}" add config/settings.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

# ── maintain-in-repo exemption for the always-blocked list (issue #186 follow-up) ──

@test "editing a protected file is allowed when this repo is the declared owner" {
    local T
    T="$(make_repo feature/maintain-exempt-shellcheckrc-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/example-server-template.git"
    mkdir -p "${T}/.no-hooks"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '# Maintain in repo: example-server-template\ncheck-sourced=false\n' > "${T}/.shellcheckrc"
    git -C "${T}" add .pre-commit-config.yaml .shellcheckrc
    git -C "${T}" commit --quiet -m baseline
    printf -- '# Maintain in repo: example-server-template\ncheck-sourced=true\n' > "${T}/.shellcheckrc"
    git -C "${T}" add .shellcheckrc
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "editing .globalconfig is still rejected when this repo is not the declared owner" {
    local T
    T="$(make_repo feature/maintain-not-exempt-globalconfig-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/some-consumer-repo.git"
    mkdir -p "${T}/.no-hooks"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '# Maintain in repo: example-server-template\n<GlobalConfig></GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .pre-commit-config.yaml .globalconfig
    git -C "${T}" commit --quiet -m baseline
    printf -- '# Maintain in repo: example-server-template\n<GlobalConfig>\n  <NoWarn>FFS0040=error</NoWarn>\n</GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .globalconfig
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "rewriting .globalconfig's ownership comment to self-authorise in the same commit is still rejected" {
    local T
    T="$(make_repo feature/maintain-globalconfig-rewrite-attack-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/some-consumer-repo.git"
    mkdir -p "${T}/.no-hooks"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf -- '# Maintain in repo: example-server-template\n<GlobalConfig></GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .pre-commit-config.yaml .globalconfig
    git -C "${T}" commit --quiet -m baseline
    printf -- '# Maintain in repo: some-consumer-repo\n<GlobalConfig></GlobalConfig>\n' > "${T}/.globalconfig"
    git -C "${T}" add .globalconfig
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging .gitleaks (no extension) in non-hooks repo is rejected (was a pre-existing naming bug)" {
    local T
    T="$(make_repo feature/gitleaks-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '[allowlist]\n' > "${T}/.gitleaks"
    git -C "${T}" add .pre-commit-config.yaml .gitleaks
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging .gitattributes in non-hooks repo is rejected (was missing entirely)" {
    local T
    T="$(make_repo feature/gitattributes-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '* text=auto\n' > "${T}/.gitattributes"
    git -C "${T}" add .pre-commit-config.yaml .gitattributes
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "staging .yamllint.yml in non-hooks repo is rejected (was a pre-existing naming bug)" {
    local T
    T="$(make_repo feature/yamllint-nonhooks-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'rules: {}\n' > "${T}/.yamllint.yml"
    git -C "${T}" add .pre-commit-config.yaml .yamllint.yml
    run_hook "${T}"
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
