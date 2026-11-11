#!/usr/bin/env bats
# Tests for which bats files run-bats selects when it is given staged files.
# shellcheck disable=SC2154  # status/output are set by bats' run

load test_helper

# write_marker_test <file> <test name> <comment>
# Writes a one-test bats file whose passing test is named <test name>, with
# <comment> as a comment line so the file can mention a path.
write_marker_test() {
    printf '#!/usr/bin/env bats\n# %s\n@test "%s" {\n  true\n}\n' "$3" "$2" > "$1"
}

# make_affected_repo
# Creates a fixture repo whose test/ suite has one marker test per file, so a
# run's output shows exactly which files bats ran:
#   test/alpha-tool.bats  marker-alpha  (named after src/scripts/alpha-tool.sh)
#   test/beta.bats        marker-beta   (mentions src/scripts/shared-tool.sh)
#   test/gamma.bats       marker-gamma  (mentions shared-tool.sh)
#   test/delta.bats       marker-delta  (mentions nothing)
#   test/odd ref.bats     marker-odd    (mentions src/scripts/my script.sh)
#   test/ünï.bats         marker-unicode
#   test/util-lib.bats    marker-util     (named after src/scripts/lib/util-lib.sh,
#                                          which no fixture file sources)
#   test/alias-tool.bats  marker-alias    (named after src/scripts/alias-tool.sh,
#                                          a symlink to alpha-tool.sh)
make_affected_repo() {
    local _t
    _t="$(make_repo feature/bats-affected)"
    mkdir -p "${_t}/test" "${_t}/src/scripts/lib"
    write_marker_test "${_t}/test/alpha-tool.bats" marker-alpha "no references"
    write_marker_test "${_t}/test/beta.bats" marker-beta "covers src/scripts/shared-tool.sh"
    write_marker_test "${_t}/test/gamma.bats" marker-gamma "calls shared-tool.sh"
    write_marker_test "${_t}/test/delta.bats" marker-delta "no references"
    write_marker_test "${_t}/test/odd ref.bats" marker-odd "covers src/scripts/my script.sh"
    write_marker_test "${_t}/test/ünï.bats" marker-unicode "no references"
    write_marker_test "${_t}/test/util-lib.bats" marker-util "no references"
    write_marker_test "${_t}/test/alias-tool.bats" marker-alias "no references"
    printf 'helper() { true; }\n' > "${_t}/test/test_helper.bash"
    local _script
    for _script in alpha-tool.sh shared-tool.sh "my script.sh" orphan.sh lib/util-lib.sh; do
        printf '#!/bin/sh\necho hello\n' > "${_t}/src/scripts/${_script}"
    done
    ln -s alpha-tool.sh "${_t}/src/scripts/alias-tool.sh"
    printf '%s' "${_t}"
}

ALL_MARKERS=(marker-alpha marker-beta marker-gamma marker-delta marker-odd marker-unicode marker-util marker-alias)

# assert_ran_only <status> <output> <marker>...
# Passes when the run succeeded and ran exactly the named marker tests.
assert_ran_only() {
    local _status="$1" _output="$2" _marker
    shift 2
    [ "${_status}" -eq 0 ] || fail_with_run_output "${_status}" "${_output}" 0
    for _marker in "${ALL_MARKERS[@]}"; do
        case " $* " in
            *" ${_marker} "*)
                [[ "${_output}" == *"ok "*" ${_marker}"* ]] ||
                    fail_with_run_output "${_status}" "${_output}" "0 with ${_marker} run"
                ;;
            *)
                [[ "${_output}" != *" ${_marker}"* ]] ||
                    fail_with_run_output "${_status}" "${_output}" "0 without ${_marker} run"
                ;;
        esac
    done
}

assert_ran_full_suite() {
    assert_ran_only "$1" "$2" "${ALL_MARKERS[@]}"
}

# run_affected <repo> <arg>...
# Runs run-bats with <arg>... from <repo> through run_isolated.
run_affected() {
    local _repo="$1"
    shift
    run_isolated "${_repo}" "${TEST_PATH}" "${REPO_DIR}/src/scripts/run-bats" "$@"
}

# T is the fixture repo from make_affected_repo, rebuilt for every test.
setup() {
    command -v bats > /dev/null 2>&1 || skip "bats not installed"
    T="$(make_affected_repo)"
}

@test "run-bats with a staged .bats file under test/ runs only that file" {
    run_affected "${T}" test/delta.bats
    assert_ran_only "${status}" "${output}" marker-delta
}

@test "run-bats with a script runs the test file named after it" {
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats with a script referenced by several tests runs all of them and no others" {
    run_affected "${T}" src/scripts/shared-tool.sh
    assert_ran_only "${status}" "${output}" marker-beta marker-gamma
}

@test "run-bats with several files runs the union of their tests" {
    run_affected "${T}" src/scripts/alpha-tool.sh test/delta.bats README.md
    assert_ran_only "${status}" "${output}" marker-alpha marker-delta
}

@test "run-bats with an absolute path inside the repo maps it like a relative one" {
    run_affected "${T}" "${T}/src/scripts/alpha-tool.sh"
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats with an absolute path through a symlinked repo root maps it like a relative one" {
    ln -s "${T}" "${BATS_TEST_TMPDIR}/repo-link"
    run_affected "${T}" "${BATS_TEST_TMPDIR}/repo-link/src/scripts/alpha-tool.sh"
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats from a subdirectory resolves a relative .bats path against the repo root" {
    run_affected "${T}/src" test/delta.bats
    assert_ran_only "${status}" "${output}" marker-delta
}

@test "run-bats from a subdirectory resolves a relative extensionless script against the repo root" {
    printf '#!/bin/sh\necho hello\n' > "${T}/src/scripts/delta"
    run_affected "${T}/src" src/scripts/delta
    assert_ran_only "${status}" "${output}" marker-delta
}

@test "run-bats from a subdirectory with an absolute path to src/.pre-commit-config.yaml runs the full suite" {
    printf 'repos: []\n' > "${T}/src/.pre-commit-config.yaml"
    run_affected "${T}/src" "${T}/src/.pre-commit-config.yaml"
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a .pre-commit-config.yaml outside src/ does not treat it as qualifying" {
    mkdir -p "${T}/other"
    printf 'repos: []\n' > "${T}/other/.pre-commit-config.yaml"
    run_affected "${T}" other/.pre-commit-config.yaml src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats maps a symlinked script by its own name, not its target's" {
    run_affected "${T}" src/scripts/alias-tool.sh
    assert_ran_only "${status}" "${output}" marker-alias
}

@test "run-bats with a symlink under test/ to a mapped script runs the full suite" {
    ln -s ../src/scripts/alpha-tool.sh "${T}/test/linked-tool.sh"
    run_affected "${T}" test/linked-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with every .bats file under test/ runs every test file" {
    run_affected "${T}" test/alpha-tool.bats test/beta.bats test/gamma.bats test/delta.bats "test/odd ref.bats" "test/ünï.bats" test/util-lib.bats test/alias-tool.bats
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with test/test_helper.bash runs the full suite" {
    run_affected "${T}" test/test_helper.bash
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a shell script no test mentions runs the full suite" {
    run_affected "${T}" src/scripts/orphan.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with src/.pre-commit-config.yaml runs the full suite" {
    printf 'repos: []\n' > "${T}/src/.pre-commit-config.yaml"
    run_affected "${T}" src/.pre-commit-config.yaml
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a .bats file outside test/ runs the full suite" {
    write_marker_test "${T}/src/elsewhere.bats" marker-elsewhere "outside test/"
    run_affected "${T}" src/elsewhere.bats
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a deleted .bats file under test/ runs the full suite" {
    run_affected "${T}" test/removed.bats
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a file outside the repo runs the full suite" {
    printf '#!/bin/sh\necho hello\n' > "${BATS_TEST_TMPDIR}/outside.sh"
    run_affected "${T}" "${BATS_TEST_TMPDIR}/outside.sh"
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a mapped script and an unmapped script runs the full suite" {
    run_affected "${T}" src/scripts/alpha-tool.sh src/scripts/orphan.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats --all-files runs the full suite" {
    commit_without_hooks "${T}" . > /dev/null
    run_bats_all_files "${T}"
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with no arguments runs the full suite" {
    run_affected "${T}"
    assert_ran_full_suite "${status}" "${output}"
}

@test "RUN_BATS_FULL=1 makes run-bats run the full suite for a mappable file" {
    run_isolated "${T}" "${TEST_PATH}" env RUN_BATS_FULL=1 "${REPO_DIR}/src/scripts/run-bats" test/delta.bats
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats maps a script whose name contains a space" {
    run_affected "${T}" "src/scripts/my script.sh"
    assert_ran_only "${status}" "${output}" marker-odd
}

@test "run-bats runs a staged .bats file with a space in its name" {
    run_affected "${T}" "test/odd ref.bats"
    assert_ran_only "${status}" "${output}" marker-odd
}

@test "run-bats runs a staged .bats file with a non-ASCII name" {
    run_affected "${T}" "test/ünï.bats"
    assert_ran_only "${status}" "${output}" marker-unicode
}

# write_script <repo> <path> <line>...
# Writes <repo>/<path>, a sh script whose body is <line>..., so a test can
# make it run or source another fixture file.
write_script() {
    local _repo="$1" _path="$2"
    shift 2
    { printf '#!/bin/sh\n'; printf '%s\n' "$@"; } > "${_repo}/${_path}"
}

# write_sourcing_script <repo> <line>...
# Writes src/scripts/user-tool.sh, a script no test names, whose body is
# <line>..., so a test can make it source src/scripts/lib/util-lib.sh in a
# given form.
write_sourcing_script() {
    local _repo="$1"
    shift
    write_script "${_repo}" src/scripts/user-tool.sh "$@"
}

@test "run-bats with a library no other file sources narrows to its tests" {
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_only "${status}" "${output}" marker-util
}

@test "run-bats with a script another script runs adds the tests of the script that runs it" {
    # shellcheck disable=SC2016 # literal script text, written to the fixture unexpanded
    write_script "${T}" src/scripts/delta 'sh "$(dirname "$0")/alpha-tool.sh"'
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha marker-delta
}

@test "run-bats with a library a tested script sources adds the tests of that script" {
    # shellcheck disable=SC2016 # literal script text, written to the fixture unexpanded
    write_script "${T}" src/scripts/delta '. "$(dirname "$0")/lib/util-lib.sh"'
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_only "${status}" "${output}" marker-util marker-delta
}

@test "run-bats with a script named by a committed script adds that script's tests" {
    write_script "${T}" src/scripts/delta 'sh ./alpha-tool.sh'
    commit_without_hooks "${T}" . > /dev/null
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha marker-delta
}

@test "run-bats looks for files naming a script outside src/" {
    mkdir -p "${T}/tools"
    write_script "${T}" tools/delta 'sh ../src/scripts/alpha-tool.sh'
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha marker-delta
}

@test "run-bats goes only one level up from a changed script" {
    write_script "${T}" src/scripts/delta 'sh ./alpha-tool.sh'
    write_script "${T}" src/scripts/gamma 'sh ./delta'
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha marker-delta
}

@test "run-bats ignores a file that names a script but does not qualify" {
    printf 'Run src/scripts/alpha-tool.sh to start.\n' > "${T}/README.md"
    printf 'see alpha-tool.sh\n' > "${T}/src/scripts/NOTES"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats with a script named by a test helper runs the full suite" {
    printf 'helper() { sh src/scripts/alpha-tool.sh; }\n' > "${T}/test/test_helper.bash"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a script named by src/.pre-commit-config.yaml runs the full suite" {
    printf 'repos:\n  - hooks:\n      - entry: alpha-tool.sh\n' > "${T}/src/.pre-commit-config.yaml"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a script named by a script with no tests runs the full suite" {
    write_script "${T}" src/scripts/user-tool.sh 'sh ./alpha-tool.sh'
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a library another script sources with . runs the full suite" {
    # shellcheck disable=SC2016 # literal script text, written to the fixture unexpanded
    write_sourcing_script "${T}" 'SCRIPT_DIR=$(dirname "$0")' '. "$SCRIPT_DIR/lib/util-lib.sh"'
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a library another script sources with source runs the full suite" {
    # shellcheck disable=SC2016 # literal script text, written to the fixture unexpanded
    write_sourcing_script "${T}" '[ -n "$1" ] && source "$(dirname "$0")/lib/util-lib.sh"'
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a library named only by a shellcheck source directive runs the full suite" {
    # shellcheck disable=SC2016 # literal script text, written to the fixture unexpanded
    write_sourcing_script "${T}" '# shellcheck source=src/scripts/lib/util-lib.sh' '. "$LIB"'
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a library sourced by a committed script runs the full suite" {
    write_sourcing_script "${T}" '. ./lib/util-lib.sh'
    commit_without_hooks "${T}" . > /dev/null
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats does not treat a library as sourced when a source line names a longer file ending in its name" {
    # shellcheck disable=SC2016 # literal script text, written to the fixture unexpanded
    write_sourcing_script "${T}" '. "$(dirname "$0")/lib/my-util-lib.sh"'
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_only "${status}" "${output}" marker-util
}

# commit_fixture_and_stage_removal <repo> <path>...
# Commits the whole fixture, then stages the removal of each <path>, as a
# commit deleting those files would before pre-commit runs.
commit_fixture_and_stage_removal() {
    local _repo="$1"
    shift
    commit_without_hooks "${_repo}" . > /dev/null
    git -C "${_repo}" rm --quiet -- "$@"
}

# stage_edit <repo> <path>...
# Appends a line to each <path> and stages it, so the path is part of the
# staged change, as every file pre-commit passes to a commit run is.
stage_edit() {
    local _repo="$1" _path
    shift
    for _path in "$@"; do
        printf '# edited\n' >> "${_repo}/${_path}"
        git -C "${_repo}" add -- "${_path}"
    done
}

# run_affected_range <repo> <from> <to> <arg>...
# Runs run-bats with <arg>... from <repo> as pre-commit runs a hook for
# `pre-commit run --from-ref <from> --to-ref <to>`, and for a pre-push.
run_affected_range() {
    local _repo="$1" _from="$2" _to="$3"
    shift 3
    run_isolated "${_repo}" "${TEST_PATH}" env PRE_COMMIT_FROM_REF="${_from}" PRE_COMMIT_TO_REF="${_to}" \
        "${REPO_DIR}/src/scripts/run-bats" "$@"
}

@test "run-bats with a staged deletion of a script runs the full suite when narrowing another" {
    commit_fixture_and_stage_removal "${T}" src/scripts/alpha-tool.sh
    stage_edit "${T}" src/scripts/shared-tool.sh
    run_affected "${T}" src/scripts/shared-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged deletion of a script runs the full suite when no passed file qualifies" {
    commit_fixture_and_stage_removal "${T}" src/scripts/alpha-tool.sh
    stage_edit "${T}" README.md
    run_affected "${T}" README.md
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged deletion of a test helper under test/ runs the full suite" {
    commit_fixture_and_stage_removal "${T}" test/test_helper.bash
    stage_edit "${T}" src/scripts/alpha-tool.sh
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged deletion of an extensionless script runs the full suite" {
    printf '#!/usr/bin/env bash\necho hello\n' > "${T}/src/scripts/plain-tool"
    commit_fixture_and_stage_removal "${T}" src/scripts/plain-tool
    stage_edit "${T}" src/scripts/alpha-tool.sh
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged rename of a script runs the full suite" {
    commit_without_hooks "${T}" . > /dev/null
    git -C "${T}" mv src/scripts/alpha-tool.sh src/scripts/alpha-renamed.sh
    stage_edit "${T}" src/scripts/shared-tool.sh
    run_affected "${T}" src/scripts/shared-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged deletion of a non-shell file still narrows" {
    printf 'docs\n' > "${T}/README.md"
    printf 'no shebang\n' > "${T}/src/scripts/NOTES"
    commit_fixture_and_stage_removal "${T}" README.md src/scripts/NOTES
    stage_edit "${T}" src/scripts/alpha-tool.sh
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats ignores a leftover staged deletion when a passed file is not part of the staged change" {
    # As `pre-commit run --files` or --all-files does with a deletion left
    # staged: the passed file is not in the staged change, so the deletion is
    # not part of what is being checked.
    commit_fixture_and_stage_removal "${T}" src/scripts/alpha-tool.sh
    run_affected "${T}" src/scripts/shared-tool.sh
    assert_ran_only "${status}" "${output}" marker-beta marker-gamma
}

@test "run-bats with a deletion in a --from-ref/--to-ref range runs the full suite" {
    commit_fixture_and_stage_removal "${T}" src/scripts/alpha-tool.sh
    stage_edit "${T}" src/scripts/shared-tool.sh
    commit_without_hooks "${T}" . > /dev/null
    run_affected_range "${T}" HEAD~1 HEAD src/scripts/shared-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a deletion of a non-shell file in a range still narrows, reading it from the range's base" {
    printf 'no shebang\n' > "${T}/src/scripts/NOTES"
    commit_fixture_and_stage_removal "${T}" src/scripts/NOTES
    stage_edit "${T}" src/scripts/shared-tool.sh
    commit_without_hooks "${T}" . > /dev/null
    run_affected_range "${T}" HEAD~1 HEAD src/scripts/shared-tool.sh
    assert_ran_only "${status}" "${output}" marker-beta marker-gamma
}

@test "run-bats in a range run ignores a deletion staged outside the range" {
    commit_without_hooks "${T}" . > /dev/null
    stage_edit "${T}" src/scripts/shared-tool.sh
    commit_without_hooks "${T}" . > /dev/null
    git -C "${T}" rm --quiet -- src/scripts/alpha-tool.sh
    run_affected_range "${T}" HEAD~1 HEAD src/scripts/shared-tool.sh
    assert_ran_only "${status}" "${output}" marker-beta marker-gamma
}

@test "run-bats runs the full suite when the index cannot be read" {
    commit_without_hooks "${T}" . > /dev/null
    printf 'not an index' > "${T}/.git/index"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged deletion whose HEAD blob is missing runs the full suite" {
    printf 'no shebang\n' > "${T}/src/scripts/NOTES"
    commit_fixture_and_stage_removal "${T}" src/scripts/NOTES
    stage_edit "${T}" src/scripts/alpha-tool.sh
    local _oid
    _oid=$(git -C "${T}" rev-parse HEAD:src/scripts/NOTES)
    rm -f "${T}/.git/objects/${_oid:0:2}/${_oid:2}"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_full_suite "${status}" "${output}"
}

@test "run-bats with a staged deletion of a large non-shell file still narrows" {
    {
        printf 'no shebang\n'
        head -c 1048576 /dev/zero | tr '\000' 'x'
        printf '\n'
    } > "${T}/src/scripts/BIG"
    commit_fixture_and_stage_removal "${T}" src/scripts/BIG
    stage_edit "${T}" src/scripts/alpha-tool.sh
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha
}

@test "run-bats adds a test marked to run always to a narrowed run" {
    write_marker_test "${T}/test/delta.bats" marker-delta "run-bats: always"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha marker-delta
}

@test "run-bats runs no test marked to run always when no file qualifies" {
    write_marker_test "${T}/test/delta.bats" marker-delta "run-bats: always"
    printf 'notes\n' > "${T}/README.md"
    run_affected "${T}" README.md
    assert_ran_only "${status}" "${output}"
}

@test "run-bats ignores a run-always mention that is not a whole comment line" {
    write_marker_test "${T}/test/delta.bats" marker-delta "see run-bats: always"
    run_affected "${T}" src/scripts/alpha-tool.sh
    assert_ran_only "${status}" "${output}" marker-alpha
}
