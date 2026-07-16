#!/usr/bin/env bats
# SQL linter acceptance tests (sqlfluff + tsqllint).
# Skipped when sqlfluff is absent or when dotnet is present but tsqllint is not
# installed globally (tsqllint cannot be resolved from isolated temp repos).

load test_helper

_sql_tools_available() {
    command -v sqlfluff > /dev/null 2>&1 || return 1
    if command -v dotnet > /dev/null 2>&1; then
        # tsqllint must be directly on PATH because isolated test repos live under
        # /tmp (noexec on this system) where local dotnet tool manifests are absent
        # and dotnet cannot invoke global tools that are not on PATH.
        command -v tsqllint > /dev/null 2>&1 || return 1
    fi
    return 0
}

@test "invalid SQL (parse error) is rejected" {
    if ! _sql_tools_available; then
        skip "sqlfluff not installed or tsqllint not installed globally"
    fi
    local T
    T="$(make_repo feature/invalid-sql-test)"
    # .sqlfluff/.tsqllintrc are on the protected-everywhere list (#187) and can
    # never be added through the real hook, so they must be committed as a
    # baseline (hook bypassed via a scratch core.hooksPath, same pattern as
    # test/core.bats) before the diff under test — otherwise this test would
    # only pass because the protected-config check rejects the commit, not
    # because of the SQL parse error it claims to cover.
    mkdir -p "${T}/.no-hooks"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '[sqlfluff]\ndialect = ansi\n' > "${T}/.sqlfluff"
    cp "${REPO_DIR}/.tsqllintrc" "${T}/.tsqllintrc"
    git -C "${T}" add .pre-commit-config.yaml .sqlfluff .tsqllintrc
    git -C "${T}" commit --quiet -m baseline
    printf 'SELECT FROM WHERE;\n' > "${T}/broken.sql"
    git -C "${T}" add broken.sql
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid SQL passes" {
    if ! _sql_tools_available; then
        skip "sqlfluff not installed or tsqllint not installed globally"
    fi
    local T
    T="$(make_repo feature/valid-sql-test)"
    # See "invalid SQL (parse error) is rejected" above for why the config
    # files need a baseline commit ahead of the diff under test.
    mkdir -p "${T}/.no-hooks"
    git -C "${T}" config core.hooksPath "${T}/.no-hooks"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '[sqlfluff]\ndialect = ansi\n' > "${T}/.sqlfluff"
    cp "${REPO_DIR}/.tsqllintrc" "${T}/.tsqllintrc"
    git -C "${T}" add .pre-commit-config.yaml .sqlfluff .tsqllintrc
    git -C "${T}" commit --quiet -m baseline
    printf 'SELECT id FROM dbo.users;\n' > "${T}/clean.sql"
    git -C "${T}" add clean.sql
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
