#!/usr/bin/env bats
# Acceptance tests for src/scripts/check-funfair-props:
# - src/FunFair.props is left alone when origin is owned by funfair-tech
#   (any URL form, case-insensitive) or when there is no origin remote
# - otherwise a tracked copy is git rm'd (removal staged) and an untracked
#   copy is deleted, failing in both cases; a re-run then passes
# - under git commit -a, -i and <paths> (a temporary index) a tracked copy is
#   only deleted, and the message says how to stage the removal; so is a copy
#   whose addition is staged but not in HEAD (absent from a <paths> index);
#   the advice lists src/FunFair.props among the paths only when HEAD has it
# - a staged-only copy already deleted from the working tree does not block a
#   git commit -a or <paths> commit; the next plain commit removes it
# - only the exact path src/FunFair.props relative to the repo root counts

load test_helper

CHECK_FUNFAIR_PROPS="${REPO_DIR}/src/scripts/check-funfair-props"
PROPS_FILE="src/FunFair.props"
OTHER_ORIGIN="git@github.com:credfeto/widget.git"

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
    local _origin="$1"
    local _t
    _t="$(make_repo)"
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

# Creates a non-funfair repo with src/FunFair.props and readme.txt committed,
# then modifies readme.txt so there is a change to commit, and prints its path.
# The empty project pre-commit config keeps the hook off the bundled global
# linters, so a commit that should pass is not failed by an unrelated linter or
# its environment (e.g. ansible-lint on a runner with mismatched versions).
make_committed_props_repo() {
    local _t
    _t="$(make_props_repo "${OTHER_ORIGIN}")"
    write_props_file "${_t}"
    printf 'repos: []\n' > "${_t}/.pre-commit-config.yaml"
    printf 'one\n' > "${_t}/readme.txt"
    commit_without_hooks "${_t}" .
    printf 'two\n' >> "${_t}/readme.txt"
    printf '%s' "${_t}"
}

# Runs a real `git commit --quiet <args>` in repo "$1", so the hook runs with
# the GIT_INDEX_FILE git chooses for that form of commit, in the same
# environment run_hook gives the hook. Sets $status and $output via bats run.
run_git_commit() {
    local _repo="$1"
    shift
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        _path="$2"
        shift 2
        env PATH="${_path}" git commit --quiet "$@"
    ' _ "${_repo}" "${TEST_PATH}" "$@"
}

# Succeeds when HEAD's commit records the deletion of src/FunFair.props.
head_deletes_props() {
    [[ "$(git -C "$1" show --name-status --format= HEAD)" == *"D	${PROPS_FILE}"* ]]
}

# Creates a non-funfair repo with readme.txt committed and modified, and
# src/FunFair.props added to the index but never committed, then deleted from
# the working tree, and prints its path.
make_staged_then_deleted_props_repo() {
    local _t
    _t="$(make_props_repo "${OTHER_ORIGIN}")"
    printf 'repos: []\n' > "${_t}/.pre-commit-config.yaml"
    printf 'one\n' > "${_t}/readme.txt"
    commit_without_hooks "${_t}" .
    write_props_file "${_t}"
    git -C "${_t}" add -- "${PROPS_FILE}"
    rm -- "${_t}/${PROPS_FILE}"
    printf 'two\n' >> "${_t}/readme.txt"
    printf '%s' "${_t}"
}

# Succeeds when src/FunFair.props is in neither HEAD, the index nor the
# working tree of the given repo.
props_fully_removed() {
    ! git -C "$1" cat-file -e "HEAD:${PROPS_FILE}" 2>/dev/null \
        && is_untracked "$1" "${PROPS_FILE}" \
        && [ ! -e "$1/${PROPS_FILE}" ] \
        && [ -z "$(git -C "$1" status --porcelain -- "${PROPS_FILE}")" ]
}

@test "funfair-tech origin in any URL form and case keeps a tracked src/FunFair.props" {
    local T _remote
    T="$(make_props_repo "${FUNFAIR_REMOTES[0]}")"
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
    local T _remote
    T="$(make_props_repo "${OTHER_REMOTES[0]}")"
    for _remote in "${OTHER_REMOTES[@]}"; do
        git -C "${T}" remote set-url origin "${_remote}"
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
    T="$(make_props_repo "${OTHER_ORIGIN}")"
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
    T="$(make_props_repo "${OTHER_ORIGIN}")"
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
    T="$(make_props_repo "${OTHER_ORIGIN}")"
    run_check_funfair_props "${T}"
    [ "${status}" -eq 0 ]
}

@test "no origin remote keeps a tracked src/FunFair.props" {
    local T
    T="$(make_props_repo "")"
    git -C "${T}" remote add upstream "${OTHER_ORIGIN}"
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
    T="$(make_props_repo "${OTHER_ORIGIN}")"
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
    T="$(make_props_repo "${OTHER_ORIGIN}")"
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    mkdir -p "${T}/docs"
    run_check_funfair_props "${T}/docs"
    [ "${status}" -eq 1 ]
    is_untracked "${T}" "${PROPS_FILE}"
}

@test "pre-commit hook fails and stages the removal when check-funfair-props fails" {
    local T
    T="$(make_props_repo "${OTHER_ORIGIN}")"
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    run_hook "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"src/FunFair.props is not permitted outside funfair-tech repositories"* ]]
    is_untracked "${T}" "${PROPS_FILE}"
}

@test "pre-commit hook --all-files fails and deletes the file when check-funfair-props fails" {
    local T
    T="$(make_props_repo "${OTHER_ORIGIN}")"
    write_props_file "${T}"
    commit_without_hooks "${T}" "${PROPS_FILE}"
    run_hook_all_files "${T}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"src/FunFair.props is not permitted outside funfair-tech repositories"* ]]
    is_untracked "${T}" "${PROPS_FILE}"
}

# git commit -a, -i and <paths> run the hook against a temporary index that
# git discards when the hook fails, so the removal can only be staged by a
# plain git commit; the tests below drive each form through the real hook.

@test "plain git commit stages the removal and the re-run commits the deletion" {
    local T
    T="$(make_committed_props_repo)"
    git -C "${T}" add -- readme.txt

    run_git_commit "${T}" -m change
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"its removal has been staged"* ]]
    run git -C "${T}" diff --cached --name-status -- "${PROPS_FILE}"
    [ "${output}" = "D	${PROPS_FILE}" ]

    run_git_commit "${T}" -m change
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    head_deletes_props "${T}"
}

@test "git commit -a deletes the file without claiming it is staged and the re-run commits the deletion" {
    local T
    T="$(make_committed_props_repo)"

    run_git_commit "${T}" -a -m change
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"the removal could not be staged"* ]]
    [[ "${output}" != *"its removal has been staged"* ]]
    [ ! -e "${T}/${PROPS_FILE}" ]
    is_tracked "${T}" "${PROPS_FILE}"

    run_git_commit "${T}" -a -m change
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    head_deletes_props "${T}"
}

@test "git commit <paths> passes once the deletion is staged and src/FunFair.props is listed" {
    local T
    T="$(make_committed_props_repo)"

    run_git_commit "${T}" -m change readme.txt
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"the removal could not be staged"* ]]
    [[ "${output}" == *"must also list ${PROPS_FILE} among its paths"* ]] || fail_test "expected the advice to list the file, got: ${output}"
    [ ! -e "${T}/${PROPS_FILE}" ]
    is_tracked "${T}" "${PROPS_FILE}"

    git -C "${T}" rm --ignore-unmatch --quiet -- "${PROPS_FILE}"
    # The temporary index is rebuilt from HEAD for the listed paths only, so
    # the staged deletion is not seen unless src/FunFair.props is listed too.
    run_git_commit "${T}" -m change readme.txt
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"its removal is already staged but this commit's paths do not include it"* ]]

    run_git_commit "${T}" -m change readme.txt "${PROPS_FILE}"
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    head_deletes_props "${T}"
}

@test "git commit -i <paths> passes once the deletion is staged" {
    local T
    T="$(make_committed_props_repo)"

    run_git_commit "${T}" -i -m change readme.txt
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"the removal could not be staged"* ]]
    is_tracked "${T}" "${PROPS_FILE}"

    git -C "${T}" rm --ignore-unmatch --quiet -- "${PROPS_FILE}"
    run_git_commit "${T}" -i -m change readme.txt
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    head_deletes_props "${T}"
}

@test "git commit <paths> gives the git rm instruction for a src/FunFair.props only staged in the repository index" {
    local T
    T="$(make_props_repo "${OTHER_ORIGIN}")"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'one\n' > "${T}/readme.txt"
    commit_without_hooks "${T}" .
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    printf 'two\n' >> "${T}/readme.txt"

    # The temporary index is built from HEAD, which has never held the file,
    # so only the repository's own index shows the staged addition.
    run_git_commit "${T}" -m change readme.txt
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"git rm --ignore-unmatch --quiet -- ${PROPS_FILE}"* ]] || fail_test "expected the git rm instruction, got: ${output}"
    [[ "${output}" != *"the untracked file has been deleted"* ]]
    [ ! -e "${T}/${PROPS_FILE}" ]
    is_tracked "${T}" "${PROPS_FILE}"

    git -C "${T}" rm --ignore-unmatch --quiet -- "${PROPS_FILE}"
    run_git_commit "${T}" -m change readme.txt
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    props_fully_removed "${T}"
}

@test "git commit <paths> listing a never-committed src/FunFair.props passes once the advice to leave it out is followed" {
    local T
    T="$(make_props_repo "${OTHER_ORIGIN}")"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    printf 'one\n' > "${T}/readme.txt"
    commit_without_hooks "${T}" .
    write_props_file "${T}"
    git -C "${T}" add -- "${PROPS_FILE}"
    printf 'two\n' >> "${T}/readme.txt"

    run_git_commit "${T}" -m change -- "${PROPS_FILE}" readme.txt
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"git rm --ignore-unmatch --quiet -- ${PROPS_FILE}"* ]] || fail_test "expected the git rm instruction, got: ${output}"
    [[ "${output}" == *"must not list ${PROPS_FILE} among its paths"* ]] || fail_test "expected the advice to leave the file out, got: ${output}"
    [[ "${output}" != *"must also list"* ]]

    # HEAD has never held the file, so once its addition is unstaged git
    # rejects it as a path ("did not match any file(s) known to git").
    git -C "${T}" rm --ignore-unmatch --quiet -- "${PROPS_FILE}"
    run_git_commit "${T}" -m change -- readme.txt
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    props_fully_removed "${T}"
}

@test "a staged-only src/FunFair.props left in the index by git commit <paths> is removed by the next plain git commit" {
    local T
    T="$(make_staged_then_deleted_props_repo)"

    # The file is gone from the working tree, so the paths commit cannot add
    # it to HEAD and passes, leaving the stale addition in the index.
    run_git_commit "${T}" -m change readme.txt
    [ "${status}" -eq 0 ] || fail_test "expected pass, got ${status}: ${output}"
    run git -C "${T}" cat-file -e "HEAD:${PROPS_FILE}"
    [ "${status}" -ne 0 ]
    is_tracked "${T}" "${PROPS_FILE}"

    printf 'three\n' >> "${T}/readme.txt"
    git -C "${T}" add -- readme.txt
    run_git_commit "${T}" -m change
    [ "${status}" -eq 1 ] || fail_test "expected failure, got ${status}: ${output}"
    [[ "${output}" == *"its removal has been staged"* ]] || fail_test "expected the staged removal message, got: ${output}"
    props_fully_removed "${T}"

    run_git_commit "${T}" -m change
    [ "${status}" -eq 0 ] || fail_test "expected re-run to pass, got ${status}: ${output}"
    props_fully_removed "${T}"
}

@test "git commit -a passes when it removes a staged-only src/FunFair.props already deleted from the working tree" {
    local T
    T="$(make_staged_then_deleted_props_repo)"

    run_git_commit "${T}" -a -m change
    [ "${status}" -eq 0 ] || fail_test "expected pass, got ${status}: ${output}"
    props_fully_removed "${T}"
}

@test "git commit <paths> listing a staged-only src/FunFair.props already deleted from the working tree passes" {
    local T
    T="$(make_staged_then_deleted_props_repo)"

    run_git_commit "${T}" -m change "${PROPS_FILE}" readme.txt
    [ "${status}" -eq 0 ] || fail_test "expected pass, got ${status}: ${output}"
    props_fully_removed "${T}"
}
