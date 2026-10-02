#!/usr/bin/env bats
# Every place that reads a git file list must see a non-ASCII name as the
# real name. With core.quotePath at its default (true), git C-quotes such a
# name in its line-separated output (tést.js comes out as "t\303\251st.js",
# quotes included), so an extension or basename match against that output
# silently misses the file. These tests stage or track a file with an
# accented name and check that each file-list consumer still picks it up.

load test_helper

# make_shim <name> [fix-glob]
# Creates a <name> command in $BATS_TEST_TMPDIR/shim that records each call's
# arguments in $BATS_TEST_TMPDIR/<name>-calls and exits 0, and prints the
# directory holding it. With [fix-glob], a `<name> fix ...` call also appends
# a "-- fixed" line to every working-tree file matching that find -name glob,
# standing in for a fixer that rewrites files.
make_shim() {
    local _shim_dir="${BATS_TEST_TMPDIR}/shim"
    mkdir -p "${_shim_dir}"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/%s-calls"\n' "${BATS_TEST_TMPDIR}" "$1" > "${_shim_dir}/$1"
    if [ -n "${2:-}" ]; then
        # shellcheck disable=SC2016 # $1 is meant literally here: it is written
        # into the generated shim and only expands when the shim runs.
        printf '[ "$1" = fix ] && find . -name "%s" -not -path "./.git/*" -exec sh -c '"'"'printf "%%s\\n" "-- fixed" >> "$1"'"'"' _ {} \\;\n' "$2" >> "${_shim_dir}/$1"
    fi
    printf 'exit 0\n' >> "${_shim_dir}/$1"
    chmod +x "${_shim_dir}/$1"
    printf '%s' "${_shim_dir}"
}

# make_npm_repo
# Creates a repo with an empty pre-commit config and a package.json committed
# as a baseline, so a TypeScript/JS change makes the hook run `npm test`.
make_npm_repo() {
    local _t
    _t="$(make_repo feature/non-ascii-npm)"
    printf 'repos: []\n' > "${_t}/.pre-commit-config.yaml"
    printf '{ "name": "fixture", "scripts": { "test": "true" } }\n' > "${_t}/package.json"
    commit_without_hooks "${_t}" . > /dev/null
    printf '%s' "${_t}"
}

# make_empty_config_repo <branch>
# Creates a repo on <branch> with an empty pre-commit config committed as a
# baseline, so only the hook's own category checks react to what is staged.
make_empty_config_repo() {
    local _t
    _t="$(make_repo "$1")"
    printf 'repos: []\n' > "${_t}/.pre-commit-config.yaml"
    commit_without_hooks "${_t}" .pre-commit-config.yaml > /dev/null
    printf '%s' "${_t}"
}

# assert_shim_called <name> <expected args> <status> <output>
assert_shim_called() {
    { [ "$3" -eq 0 ] && grep -qxF -e "$2" "${BATS_TEST_TMPDIR}/$1-calls" 2> /dev/null; } ||
        fail_with_run_output "$3" "$4" 0
}

# ── src/hooks/pre-commit category detection ──────────────────────────────────

@test "hook detects a staged JS file with a non-ASCII name and runs npm test" {
    local T _shim_dir
    T="$(make_npm_repo)"
    _shim_dir="$(make_shim npm)"
    printf 'console.log("hello");\n' > "${T}/tést.js"
    git -C "${T}" add -- tést.js
    run_hook_env "${T}" "${_shim_dir}:${TEST_PATH}" "${BATS_TEST_TMPDIR}/xdg-cache"
    assert_shim_called npm test "${status}" "${output}"
}

@test "hook --all-files detects a tracked JS file with a non-ASCII name and runs npm test" {
    local T _shim_dir
    T="$(make_npm_repo)"
    _shim_dir="$(make_shim npm)"
    printf 'console.log("hello");\n' > "${T}/tést.js"
    commit_without_hooks "${T}" tést.js > /dev/null
    run_isolated "${T}" "${_shim_dir}:${TEST_PATH}" sh "${HOOK}" --all-files
    assert_shim_called npm test "${status}" "${output}"
}

# With the list no longer C-quoted, a backslash in a name reaches the category
# checks raw. dash's echo would read the \c in a\c.txt as "stop output" and
# hide every later file (here b.js) from detection, so the list must be
# printed with printf, not echo.
@test "hook still detects a staged JS file listed after a staged name containing a backslash" {
    local T _shim_dir
    T="$(make_npm_repo)"
    _shim_dir="$(make_shim npm)"
    printf 'notes\n' > "${T}/a\\c.txt"
    printf 'console.log("hello");\n' > "${T}/b.js"
    # --literal-pathspecs: a backslash in a pathspec is otherwise a glob escape.
    git -C "${T}" --literal-pathspecs add -- 'a\c.txt' b.js
    run_hook_env "${T}" "${_shim_dir}:${TEST_PATH}" "${BATS_TEST_TMPDIR}/xdg-cache"
    assert_shim_called npm test "${status}" "${output}"
}

@test "hook blocks a staged protected linter config under a non-ASCII directory" {
    local T
    T="$(make_empty_config_repo feature/non-ascii-protected-config)"
    mkdir -p "${T}/dócs"
    printf 'root = true\n' > "${T}/dócs/.editorconfig"
    git -C "${T}" add -- dócs/.editorconfig
    run_hook "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Linter/style config files cannot be added, changed, or deleted:"* ]]
    [[ "${output}" == *"dócs/.editorconfig"* ]]
}

@test "hook re-stages a sqlfluff fix to a SQL file with a non-ASCII name" {
    local T _shim_dir _dotnet_dir _path
    # Without dotnet on PATH the hook skips tsqllint and only runs sqlfluff,
    # which the shim below stands in for. dotnet's directory can only be
    # dropped from PATH when it does not also hold git.
    _path="${TEST_PATH}"
    _dotnet_dir="$(dirname "$(PATH="${TEST_PATH}" command -v dotnet 2> /dev/null || printf '/nonexistent/dotnet')")"
    [ -x "${_dotnet_dir}/git" ] && skip "dotnet shares a directory with git (${_dotnet_dir})"
    _path="$(printf '%s' "${_path}" | tr ':' '\n' | grep -Fxv "${_dotnet_dir}" | tr '\n' ':' | sed 's/:$//')"

    T="$(make_repo feature/non-ascii-sqlfluff)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'SELECT 1;\n' > "${T}/plain.sql"
    printf 'SELECT 2;\n' > "${T}/qüery.sql"
    commit_without_hooks "${T}" . > /dev/null
    # The ASCII-named plain.sql makes the hook detect a SQL change either way,
    # so this test covers only the re-staging of what sqlfluff fix changed.
    printf 'SELECT 10;\n' > "${T}/plain.sql"
    printf 'SELECT 20;\n' > "${T}/qüery.sql"
    git -C "${T}" add -- plain.sql qüery.sql
    _shim_dir="$(make_shim sqlfluff '*.sql')"

    run_hook_env "${T}" "${_shim_dir}:${_path}" "${BATS_TEST_TMPDIR}/xdg-cache"

    assert_shim_called sqlfluff "fix ." "${status}" "${output}"
    # Every fixed file was re-staged: nothing is left unstaged, and the
    # staged content of the non-ASCII file carries the fixer's change.
    [ -z "$(git -C "${T}" diff --name-only)" ]
    [ "$(git -C "${T}" show ":qüery.sql")" = "$(printf 'SELECT 20;\n-- fixed')" ]
}

# write_cfn_template <path>
# Writes a minimal template carrying the AWSTemplateFormatVersion marker the
# hook's CloudFormation detection looks for.
write_cfn_template() {
    printf 'AWSTemplateFormatVersion: "2010-09-09"\nResources: {}\n' > "$1"
}

@test "hook runs cfn-lint on a staged CloudFormation template with a non-ASCII name" {
    local T _shim_dir
    T="$(make_empty_config_repo feature/non-ascii-cfn)"
    _shim_dir="$(make_shim cfn-lint)"
    write_cfn_template "${T}/stöck.yaml"
    git -C "${T}" add -- stöck.yaml
    run_isolated "${T}" "${_shim_dir}:${TEST_PATH}" sh "${HOOK}"
    assert_shim_called cfn-lint "--include-checks I --template stöck.yaml" "${status}" "${output}"
}

# As for npm above: dash's echo would read the \c in a\c.txt as "stop output"
# and hide stack.yaml from the CloudFormation detection.
@test "hook runs cfn-lint on a staged CloudFormation template listed after a staged name containing a backslash" {
    local T _shim_dir
    T="$(make_empty_config_repo feature/non-ascii-cfn)"
    _shim_dir="$(make_shim cfn-lint)"
    printf 'notes\n' > "${T}/a\\c.txt"
    write_cfn_template "${T}/stack.yaml"
    # --literal-pathspecs: a backslash in a pathspec is otherwise a glob escape.
    git -C "${T}" --literal-pathspecs add -- 'a\c.txt' stack.yaml
    run_isolated "${T}" "${_shim_dir}:${TEST_PATH}" sh "${HOOK}"
    assert_shim_called cfn-lint "--include-checks I --template stack.yaml" "${status}" "${output}"
}

# ── src/scripts/lib/mode-arg.sh git_target_files ─────────────────────────────

# run_git_target_files <repo> <mode> <pattern>
# Sources lib/mode-arg.sh into sh in <repo> and prints git_target_files
# <pattern> for <mode> (commit or all-files).
run_git_target_files() {
    run sh -c '
        cd "$1" || exit 2
        die() { printf "%s\n" "$*" >&2; exit 1; }
        . "$2"
        MODE="$3"
        git_target_files "$4"
    ' _ "$1" "${REPO_DIR}/src/scripts/lib/mode-arg.sh" "$2" "$3"
}

@test "git_target_files lists a staged file with a non-ASCII name by its real name" {
    local T
    T="$(make_repo feature/non-ascii-target-staged)"
    printf 'echo hello\n' > "${T}/scrípt.sh"
    printf '# Title\n' > "${T}/README.md"
    git -C "${T}" add -- scrípt.sh README.md
    run_git_target_files "${T}" commit '\.sh$'
    [ "${status}" -eq 0 ]
    [ "${output}" = "scrípt.sh" ]
}

@test "git_target_files --all-files lists a tracked file with a non-ASCII name by its real name" {
    local T
    T="$(make_repo feature/non-ascii-target-tracked)"
    mkdir -p "${T}/sub"
    printf 'echo hello\n' > "${T}/scrípt.sh"
    printf '# Title\n' > "${T}/README.md"
    # Staging is enough to track the files (ls-files reads the index), and
    # saves a signed commit.
    git -C "${T}" add -- scrípt.sh README.md
    # Run from a subdirectory: the list must still be repo-root-relative.
    run_git_target_files "${T}/sub" all-files '\.sh$'
    [ "${status}" -eq 0 ]
    [ "${output}" = "scrípt.sh" ]
}

# ── src/scripts/check-ignored-files ──────────────────────────────────────────

@test "check-ignored-files reports a tracked ignored file with a non-ASCII name by its real name" {
    local T
    T="$(make_repo feature/non-ascii-ignored)"
    printf '*.log\n' > "${T}/.gitignore"
    printf 'log line\n' > "${T}/fóo.log"
    git -C "${T}" add .gitignore
    git -C "${T}" add --force -- fóo.log
    run sh -c 'cd "$1" && sh "$2"' _ "${T}" "${REPO_DIR}/src/scripts/check-ignored-files"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"  fóo.log"* ]]
}
