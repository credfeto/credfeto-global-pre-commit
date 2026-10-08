#!/usr/bin/env bats
# In commit mode the hook must run sqlfluff fix on, and re-stage, only the SQL
# files that are staged: fixing the whole tree would rewrite and then stage
# SQL files the user never staged. A staged SQL file that also has unstaged
# edits must stop the commit, since re-staging it would stage those edits.
# --all-files mode still fixes every tracked SQL file.
#
# sqlfluff is replaced by a shim that records its arguments and appends a
# "-- fixed" line to exactly the files it is given (every SQL file under the
# working tree for "."), so each test can see which files were targeted.

load test_helper

# make_sqlfluff_shim
# Creates the sqlfluff shim described above in $BATS_TEST_TMPDIR/shim, which
# records each call's arguments in $BATS_TEST_TMPDIR/sqlfluff-calls, and
# prints the directory holding it.
make_sqlfluff_shim() {
    local _shim_dir="${BATS_TEST_TMPDIR}/shim"
    mkdir -p "${_shim_dir}"
    {
        printf '#!/bin/sh\n'
        printf "calls='%s'\n" "${BATS_TEST_TMPDIR}/sqlfluff-calls"
        cat << 'EOF'
printf '%s\n' "$*" >> "$calls"
[ "$1" = fix ] || exit 0
shift
[ "${1:-}" = -- ] && shift
for f in "$@"; do
    if [ "$f" = . ]; then
        find . -name '*.sql' -not -path './.git/*' -exec sh -c 'printf "%s\n" "-- fixed" >> "$1"' _ {} \;
    else
        printf '%s\n' '-- fixed' >> "$f"
    fi
done
exit 0
EOF
    } > "${_shim_dir}/sqlfluff"
    chmod +x "${_shim_dir}/sqlfluff"
    printf '%s' "${_shim_dir}"
}

# set_sql_path
# Sets SQL_PATH to TEST_PATH without dotnet's directory, so the hook skips
# tsqllint and only runs sqlfluff, which the shim stands in for. dotnet's
# directory can only be dropped from PATH when it does not also hold git, so
# the test is skipped otherwise. Not called in a subshell, so skip works.
set_sql_path() {
    local _dotnet_dir
    _dotnet_dir="$(dirname "$(PATH="${TEST_PATH}" command -v dotnet 2> /dev/null || printf '/nonexistent/dotnet')")"
    [ -x "${_dotnet_dir}/git" ] && skip "dotnet shares a directory with git (${_dotnet_dir})"
    SQL_PATH="$(printf '%s' "${TEST_PATH}" | tr ':' '\n' | grep -Fxv "${_dotnet_dir}" | tr '\n' ':' | sed 's/:$//')"
}

# make_sql_repo <branch> <file>...
# Creates a repo with an empty pre-commit config and each <file> holding
# "SELECT 1;", all committed as a baseline, and prints its path.
make_sql_repo() {
    local _t _f
    _t="$(make_repo "$1")"
    shift
    printf 'repos: []\n' > "${_t}/.pre-commit-config.yaml"
    for _f in "$@"; do
        printf 'SELECT 1;\n' > "${_t}/${_f}"
    done
    commit_without_hooks "${_t}" . > /dev/null
    printf '%s' "${_t}"
}

# assert_status <expected> <status> <output>
assert_status() {
    [ "$2" -eq "$1" ] || fail_with_run_output "$2" "$3" "$1"
}

# assert_sqlfluff_called <expected args>
assert_sqlfluff_called() {
    grep -qxF -e "$1" "${BATS_TEST_TMPDIR}/sqlfluff-calls" 2> /dev/null ||
        fail_test "sqlfluff was not called with: $1"
}

# assert_content <expected> <actual>
assert_content() {
    [ "$2" = "$1" ] || fail_test "expected content [$1], got [$2]"
}

@test "hook fixes and re-stages a staged SQL file" {
    local T _shim_dir
    set_sql_path
    T="$(make_sql_repo feature/sql-restage-staged query.sql)"
    printf 'SELECT 2;\n' > "${T}/query.sql"
    git -C "${T}" add -- query.sql
    _shim_dir="$(make_sqlfluff_shim)"

    run_hook_env "${T}" "${_shim_dir}:${SQL_PATH}" "${BATS_TEST_TMPDIR}/xdg-cache"

    assert_status 0 "${status}" "${output}"
    assert_sqlfluff_called "fix -- query.sql"
    assert_content "$(printf 'SELECT 2;\n-- fixed')" "$(git -C "${T}" show :query.sql)"
    [ -z "$(git -C "${T}" diff --name-only)" ] || fail_test "the fixed file was not re-staged"
}

@test "hook neither fixes nor stages unstaged or untracked SQL files" {
    local T _shim_dir
    set_sql_path
    T="$(make_sql_repo feature/sql-restage-unstaged staged.sql unstaged.sql)"
    printf 'SELECT 2;\n' > "${T}/staged.sql"
    git -C "${T}" add -- staged.sql
    printf 'SELECT 3;\n' > "${T}/unstaged.sql"
    printf 'SELECT 4;\n' > "${T}/untracked.sql"
    _shim_dir="$(make_sqlfluff_shim)"

    run_hook_env "${T}" "${_shim_dir}:${SQL_PATH}" "${BATS_TEST_TMPDIR}/xdg-cache"

    assert_status 0 "${status}" "${output}"
    assert_sqlfluff_called "fix -- staged.sql"
    assert_content "$(printf 'SELECT 2;\n-- fixed')" "$(git -C "${T}" show :staged.sql)"
    # The unstaged and untracked files keep their content and stay out of the
    # index.
    assert_content "SELECT 3;" "$(cat "${T}/unstaged.sql")"
    assert_content "SELECT 1;" "$(git -C "${T}" show :unstaged.sql)"
    assert_content "SELECT 4;" "$(cat "${T}/untracked.sql")"
    is_untracked "${T}" untracked.sql || fail_test "untracked.sql was staged"
}

# A glob character in a staged name must not make the re-stage pick up an
# untracked file the glob also matches (q[1].sql matches q1.sql as a pathspec).
@test "hook re-stages a staged SQL file with a glob character in its name and nothing else" {
    local T _shim_dir
    set_sql_path
    T="$(make_sql_repo feature/sql-restage-glob)"
    printf 'SELECT 2;\n' > "${T}/q[1].sql"
    git -C "${T}" --literal-pathspecs add -- 'q[1].sql'
    printf 'SELECT 3;\n' > "${T}/q1.sql"
    _shim_dir="$(make_sqlfluff_shim)"

    run_hook_env "${T}" "${_shim_dir}:${SQL_PATH}" "${BATS_TEST_TMPDIR}/xdg-cache"

    assert_status 0 "${status}" "${output}"
    assert_sqlfluff_called "fix -- q[1].sql"
    assert_content "$(printf 'SELECT 2;\n-- fixed')" "$(git -C "${T}" show ':q[1].sql')"
    is_untracked "${T}" q1.sql || fail_test "q1.sql was staged"
}

@test "hook fails when a staged SQL file also has unstaged changes" {
    local T _shim_dir
    set_sql_path
    T="$(make_sql_repo feature/sql-restage-partial part.sql)"
    printf 'SELECT 2;\n' > "${T}/part.sql"
    git -C "${T}" add -- part.sql
    printf 'SELECT 3;\n' > "${T}/part.sql"
    _shim_dir="$(make_sqlfluff_shim)"

    run_hook_env "${T}" "${_shim_dir}:${SQL_PATH}" "${BATS_TEST_TMPDIR}/xdg-cache"

    assert_status 1 "${status}" "${output}"
    [[ "${output}" == *"Staged SQL files also have unstaged changes"* ]] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"  part.sql"* ]] || fail_with_run_output "${status}" "${output}" 1
    # sqlfluff fix never ran, and neither the index nor the working tree changed.
    if grep -q '^fix' "${BATS_TEST_TMPDIR}/sqlfluff-calls" 2> /dev/null; then
        fail_test "sqlfluff fix ran on a partially staged file"
    fi
    assert_content "SELECT 2;" "$(git -C "${T}" show :part.sql)"
    assert_content "SELECT 3;" "$(cat "${T}/part.sql")"
}

@test "hook --all-files fixes and re-stages every tracked SQL file" {
    local T _shim_dir
    set_sql_path
    T="$(make_sql_repo feature/sql-restage-all-files one.sql two.sql)"
    _shim_dir="$(make_sqlfluff_shim)"

    run_isolated "${T}" "${_shim_dir}:${SQL_PATH}" sh "${HOOK}" --all-files

    assert_status 0 "${status}" "${output}"
    assert_sqlfluff_called "fix ."
    assert_content "$(printf 'SELECT 1;\n-- fixed')" "$(git -C "${T}" show :one.sql)"
    assert_content "$(printf 'SELECT 1;\n-- fixed')" "$(git -C "${T}" show :two.sql)"
}
