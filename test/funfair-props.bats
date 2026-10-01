#!/usr/bin/env bats
# Acceptance tests for src/scripts/check-funfair-props:
# - src/FunFair.props is left alone when origin is owned by funfair-tech
#   (any URL form, case-insensitive) or when there is no origin remote
# - otherwise a tracked copy is git rm'd (removal staged) and an untracked
#   copy is deleted, failing in both cases; a re-run then passes
# - only the exact path src/FunFair.props relative to the repo root counts

load test_helper

CHECK_FUNFAIR_PROPS="${REPO_DIR}/src/scripts/check-funfair-props"
PROPS_FILE="src/FunFair.props"

FUNFAIR_REMOTES=(
    "git@github.com:funfair-tech/funfair-server-template.git"
    "https://github.com/funfair-tech/funfair-server-template"
    "https://github.com/funfair-tech/funfair-server-template.git"
    "ssh://git@github.com/funfair-tech/funfair-server-template"
    "git@github.com:FunFair-Tech/funfair-server-template.git"
    "https://github.com/FUNFAIR-TECH/funfair-server-template/"
)

# The last entry has funfair-tech as the repo name rather than the owner, to
# prove the owner segment, not the whole URL, is what gets compared.
OTHER_REMOTES=(
    "git@github.com:credfeto/funfair-server-template.git"
    "https://github.com/credfeto/funfair-server-template"
    "ssh://git@github.com/credfeto/funfair-server-template"
    "git@github.com:credfeto/funfair-tech.git"
)

# Runs check-funfair-props with "$1" as the working directory. Sets $status
# and $output via bats run.
run_check_funfair_props() {
    local _dir="$1"
    run bash -c 'cd "$1" && env PATH="$2" sh "$3"' \
        _ "${_dir}" "${TEST_PATH}" "${CHECK_FUNFAIR_PROPS}"
}

# Creates a repo with the given origin URL (none when empty) and prints its path.
make_props_repo() {
    local _branch="$1"
    local _origin="$2"
    local _t
    _t="$(make_repo "${_branch}")"
    if [ -n "${_origin}" ]; then
        git -C "${_t}" remote add origin "${_origin}"
    fi
    printf '%s' "${_t}"
}

write_props_file() {
    local _repo="$1"
    local _path="${2:-${PROPS_FILE}}"
    mkdir -p "$(dirname "${_repo}/${_path}")"
    printf '<Project />\n' > "${_repo}/${_path}"
}

# Commits the given path through a no-op hooksPath, so the file is tracked in
# HEAD without the hook under test running during setup.
commit_without_hooks() {
    local _repo="$1"
    local _path="$2"
    mkdir -p "${_repo}/.no-hooks"
    git -C "${_repo}" config core.hooksPath "${_repo}/.no-hooks"
    git -C "${_repo}" add -- "${_path}"
    git -C "${_repo}" commit --quiet -m baseline
    git -C "${_repo}" config core.hooksPath "${HOOKS_DIR}"
}

is_tracked() {
    [ -n "$(git -C "$1" ls-files -- "$2")" ]
}

# A bare `! cmd` never fails a bats test (bash's errexit ignores negated
# commands), so negative index checks need their own predicate.
is_untracked() {
    [ -z "$(git -C "$1" ls-files -- "$2")" ]
}

@test "funfair-tech origin in any URL form and case keeps a tracked src/FunFair.props" {
    local T _remote
    T="$(make_props_repo feature/funfair-owner-test "${FUNFAIR_REMOTES[0]}")"
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    for _remote in "${FUNFAIR_REMOTES[@]}"; do
        git -C "${T}" remote set-url origin "${_remote}"
        run_check_funfair_props "${T}"
        [ "${status}" -eq 0 ] || fail_test "expected pass for origin ${_remote}, got ${status}: ${output}"
        [ -f "${T}/${PROPS_FILE}" ] || fail_test "file deleted for origin ${_remote}"
        is_tracked "${T}" "${PROPS_FILE}" || fail_test "file untracked for origin ${_remote}"
    done
}

@test "non-funfair origin in any URL form fails and stages removal of a tracked src/FunFair.props" {
    local _remote _i=0 T
    for _remote in "${OTHER_REMOTES[@]}"; do
        _i=$((_i + 1))
        T="${BATS_TEST_TMPDIR}/other-${_i}"
        mkdir -p "${T}"
        git -C "${T}" init --quiet
        git -C "${T}" remote add origin "${_remote}"
        write_props_file "${T}"
        git -C "${T}" add -- "${PROPS_FILE}"
        run_check_funfair_props "${T}"
        [ "${status}" -eq 1 ] || fail_test "expected failure for origin ${_remote}, got ${status}: ${output}"
        [[ "${output}" == *"${PROPS_FILE}"* ]] || fail_test "output does not name the file for ${_remote}: ${output}"
        [ ! -e "${T}/${PROPS_FILE}" ] || fail_test "file still on disk for origin ${_remote}"
        is_untracked "${T}" "${PROPS_FILE}" || fail_test "file still in index for origin ${_remote}"
    done
}

@test "removal of a committed src/FunFair.props is staged as a deletion and a re-run passes" {
    local T
    T="$(make_props_repo feature/funfair-rerun-test "git@github.com:credfeto/widget.git")"
    write_props_file "${T}"
    commit_without_hooks "${T}" "${PROPS_FILE}"

    run_check_funfair_props "${T}"
    [ "${status}" -eq 1 ]
    run git -C "${T}" diff --cached --name-status
    [ "${output}" = "D	${PROPS_FILE}" ]

    run_check_funfair_props "${T}"
    [ "${status}" -eq 0 ]
}

@test "non-funfair origin fails and deletes an untracked src/FunFair.props" {
    local T
    T="$(make_props_repo feature/funfair-untracked-test "git@github.com:credfeto/widget.git")"
    write_props_file "${T}"

    run_check_funfair_props "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"untracked file has been deleted"* ]]
    [ ! -e "${T}/${PROPS_FILE}" ]

    run_check_funfair_props "${T}"
    [ "${status}" -eq 0 ]
}

@test "non-funfair origin with no src/FunFair.props passes" {
    local T
    T="$(make_props_repo feature/funfair-absent-test "git@github.com:credfeto/widget.git")"
    run_check_funfair_props "${T}"
    [ "${status}" -eq 0 ]
}

@test "no origin remote keeps a tracked src/FunFair.props" {
    local T
    T="$(make_props_repo feature/funfair-no-origin-test "")"
    git -C "${T}" remote add upstream "git@github.com:credfeto/widget.git"
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    run_check_funfair_props "${T}"
    [ "${status}" -eq 0 ]
    [ -f "${T}/${PROPS_FILE}" ]
    is_tracked "${T}" "${PROPS_FILE}"
}

@test "FunFair.props at any path other than src/FunFair.props is ignored" {
    local T _path
    local -a _paths=(FunFair.props other/src/FunFair.props src/nested/FunFair.props src/funfair.props)
    T="$(make_props_repo feature/funfair-other-path-test "git@github.com:credfeto/widget.git")"
    for _path in "${_paths[@]}"; do
        write_props_file "${T}" "${_path}"
        git -C "${T}" add -- "${_path}"
    done
    run_check_funfair_props "${T}"
    [ "${status}" -eq 0 ]
    for _path in "${_paths[@]}"; do
        [ -f "${T}/${_path}" ] || fail_test "${_path} was deleted"
        is_tracked "${T}" "${_path}" || fail_test "${_path} was untracked"
    done
}

@test "src/FunFair.props is resolved from the repo root when run in a subdirectory" {
    local T
    T="$(make_props_repo feature/funfair-subdir-test "git@github.com:credfeto/widget.git")"
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    mkdir -p "${T}/docs"
    run_check_funfair_props "${T}/docs"
    [ "${status}" -eq 1 ]
    is_untracked "${T}" "${PROPS_FILE}"
}

@test "pre-commit hook fails and stages the removal when check-funfair-props fails" {
    local T
    T="$(make_props_repo feature/funfair-hook-test "git@github.com:credfeto/widget.git")"
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"src/FunFair.props is not permitted outside funfair-tech repositories"* ]]
    is_untracked "${T}" "${PROPS_FILE}"
}

@test "pre-commit hook --all-files fails and deletes the file when check-funfair-props fails" {
    local T
    T="$(make_props_repo feature/funfair-hook-all-files-test "git@github.com:credfeto/widget.git")"
    write_props_file "${T}"
    commit_without_hooks "${T}" "${PROPS_FILE}"
    run_hook_all_files "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"src/FunFair.props is not permitted outside funfair-tech repositories"* ]]
    is_untracked "${T}" "${PROPS_FILE}"
}
