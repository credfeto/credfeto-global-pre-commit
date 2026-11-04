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
    printf 'helper() { true; }\n' > "${_t}/test/test_helper.bash"
    local _script
    for _script in alpha-tool.sh shared-tool.sh "my script.sh" orphan.sh lib/util-lib.sh; do
        printf '#!/bin/sh\necho hello\n' > "${_t}/src/scripts/${_script}"
    done
    printf '%s' "${_t}"
}

ALL_MARKERS=(marker-alpha marker-beta marker-gamma marker-delta marker-odd marker-unicode marker-util)

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

@test "run-bats with every .bats file under test/ runs every test file" {
    run_affected "${T}" test/alpha-tool.bats test/beta.bats test/gamma.bats test/delta.bats "test/odd ref.bats" "test/ünï.bats" test/util-lib.bats
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

# write_sourcing_script <repo> <line>...
# Writes src/scripts/user-tool.sh, a script whose body is <line>..., so a
# test can make it source src/scripts/lib/util-lib.sh in a given form.
write_sourcing_script() {
    local _repo="$1"
    shift
    { printf '#!/bin/sh\n'; printf '%s\n' "$@"; } > "${_repo}/src/scripts/user-tool.sh"
}

@test "run-bats with a library no other file sources narrows to its tests" {
    run_affected "${T}" src/scripts/lib/util-lib.sh
    assert_ran_only "${status}" "${output}" marker-util
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
