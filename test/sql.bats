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
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '[sqlfluff]\ndialect = ansi\n' > "${T}/.sqlfluff"
    cp "${REPO_DIR}/.tsqllintrc" "${T}/.tsqllintrc"
    printf 'SELECT FROM WHERE;\n' > "${T}/broken.sql"
    git -C "${T}" add .pre-commit-config.yaml .sqlfluff .tsqllintrc broken.sql
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid SQL passes" {
    if ! _sql_tools_available; then
        skip "sqlfluff not installed or tsqllint not installed globally"
    fi
    local T
    T="$(make_repo feature/valid-sql-test)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf '[sqlfluff]\ndialect = ansi\n' > "${T}/.sqlfluff"
    cp "${REPO_DIR}/.tsqllintrc" "${T}/.tsqllintrc"
    printf 'SELECT id FROM dbo.users;\n' > "${T}/clean.sql"
    git -C "${T}" add .pre-commit-config.yaml .sqlfluff .tsqllintrc clean.sql
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
