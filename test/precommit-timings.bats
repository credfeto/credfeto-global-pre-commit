#!/usr/bin/env bats
# Tests for the Pre-commit-Timings trailer: the timing helpers in
# src/scripts/lib/precommit-timings.sh, the commit-msg hook that writes the
# trailer, and whole commits through both hooks.

bats_require_minimum_version 1.5.0

load test_helper

TIMINGS_LIB="${REPO_DIR}/src/scripts/lib/precommit-timings.sh"
COMMIT_MSG_HOOK="${HOOKS_DIR}/commit-msg"
TRAILER_STEPS="check-identity check-merge-commits check-ignored-files check-funfair-props clean-package-lock-registry pre-commit check-changelog check-benchmark-project-names buildcheck buildtest npm-test tsqllint sqlfluff cfn-lint"

# run_lib <script>
# Runs <script> in sh with the timings library sourced. Sets $status and
# $output via bats run.
run_lib() {
    run sh -c '. "$1"; eval "$2"' _ "${TIMINGS_LIB}" "$1"
}

# verbose_fixture <file>
# Writes sample `pre-commit run --verbose` output: a passing hook with output
# that --verbose shows, a failing hook, a skipped hook and the same hook id
# run a second time.
verbose_fixture() {
    cat > "$1" << 'EOF'
[INFO] Initializing environment for local.
check yaml...............................................................Passed
- hook id: check-yaml
- duration: 0.05s

verbose passing output.......................................Passed

shellcheck...............................................................Failed
- hook id: shellcheck
- duration: 1.2s
- exit code: 1

In foo.sh line 1:
bad

run bats.............................................(no files to check)Skipped
- hook id: run-bats
check yaml again.........................................................Passed
- hook id: check-yaml
- duration: 0.25s
EOF
}

# ── timings_value ─────────────────────────────────────────────────────────────

@test "timings_print shows the total and each step that ran, one per line, and leaves out skipped steps" {
    run_lib 'timings_record check-identity 1s
        timings_record pre-commit "3s(a=0.5s,b=skipped)"
        timings_print'

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Pre-commit timings"* ]]
    [[ "${output}" =~ "    total="[0-9]+"s" ]]
    [[ "${output}" == *"    check-identity=1s"* ]]
    [[ "${output}" == *"    pre-commit=3s(a=0.5s,b=skipped)"* ]]
    [[ "${output}" != *"buildtest=skipped"* ]]
}

@test "timings_value lists the total first, then every step in order, with skipped for steps that did not run" {
    run_lib 'timings_record check-identity 1s
        timings_record pre-commit "3s(a=0.5s,b=skipped)"
        timings_record cfn-lint 2s
        timings_value'

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected="total=[0-9]+s" _step
    for _step in ${TRAILER_STEPS}; do
        case "${_step}" in
            check-identity) _expected="${_expected} check-identity=1s" ;;
            pre-commit) _expected="${_expected} pre-commit=3s\\(a=0\\.5s,b=skipped\\)" ;;
            cfn-lint) _expected="${_expected} cfn-lint=2s" ;;
            *) _expected="${_expected} ${_step}=skipped" ;;
        esac
    done
    [[ "${output}" =~ ^${_expected}$ ]] || fail_test "expected /${_expected}/, got: ${output}"
}

@test "timed_step records the step's whole seconds and returns the command's status" {
    # shellcheck disable=SC2016 # intentionally literal, expanded by the inner sh
    run_lib 'timed_step check-identity true
        timed_step buildcheck sh -c "exit 3"
        printf "status=%s\n" "$?"
        printf "%s" "$PRECOMMIT_TIMINGS_RECORDED"'

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "status=3" ]
    [[ "${lines[1]}" =~ ^check-identity=[0-9]+s$ ]]
    [[ "${lines[2]}" =~ ^buildcheck=[0-9]+s$ ]]
}

@test "timings_record_with_parts puts the parts in parentheses, and leaves them out when there are none" {
    # shellcheck disable=SC2016 # intentionally literal, expanded by the inner sh
    run_lib 'timings_record_with_parts buildtest "$(date +%s)" "restore=1s,pack=skipped"
        timings_record_with_parts pre-commit "$(date +%s)" ""
        printf "%s" "$PRECOMMIT_TIMINGS_RECORDED"'

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${lines[0]}" =~ ^buildtest=[0-9]+s\(restore=1s,pack=skipped\)$ ]]
    [[ "${lines[1]}" =~ ^pre-commit=[0-9]+s$ ]]
}

# ── pre-commit output ─────────────────────────────────────────────────────────

@test "precommit_hook_timings lists each hook id once in run order, adding repeated runs and marking skipped hooks" {
    verbose_fixture "${BATS_TEST_TMPDIR}/run.log"

    run_lib "precommit_hook_timings '${BATS_TEST_TMPDIR}/run.log'"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${output}" = "check-yaml=0.3s,shellcheck=1.2s,run-bats=skipped" ]
}

@test "precommit_hook_timings prints nothing when pre-commit ran no hooks" {
    : > "${BATS_TEST_TMPDIR}/run.log"

    run_lib "precommit_hook_timings '${BATS_TEST_TMPDIR}/run.log'"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "${output}" ]
}

@test "precommit_display_filter shows what pre-commit shows without --verbose" {
    verbose_fixture "${BATS_TEST_TMPDIR}/run.log"

    run_lib "precommit_display_filter < '${BATS_TEST_TMPDIR}/run.log'"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
    _expected="$(cat << 'EOF'
[INFO] Initializing environment for local.
check yaml...............................................................Passed
shellcheck...............................................................Failed
- hook id: shellcheck
- exit code: 1

In foo.sh line 1:
bad

run bats.............................................(no files to check)Skipped
check yaml again.........................................................Passed
EOF
)"
    [ "${output}" = "${_expected}" ] || fail_test "unexpected filtered output: ${output}"
}

@test "precommit_display_filter treats a status-like line with no hook id after it as hook output" {
    cat > "${BATS_TEST_TMPDIR}/run.log" << 'EOF'
output before any hook
passing hook.............................................................Passed
- hook id: passing
- duration: 0.1s

passing output that ends like a status...........................Passed
passing output
failing hook.............................................................Failed
- hook id: failing
- duration: 0.2s
failing output that ends like a status...........................Passed
failing output
last hook................................................................Passed
EOF

    run_lib "precommit_display_filter < '${BATS_TEST_TMPDIR}/run.log'"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
    _expected="$(cat << 'EOF'
output before any hook
passing hook.............................................................Passed
failing hook.............................................................Failed
- hook id: failing
failing output that ends like a status...........................Passed
failing output
last hook................................................................Passed
EOF
)"
    [ "${output}" = "${_expected}" ] || fail_test "unexpected filtered output: ${output}"
}

@test "precommit_display_filter and precommit_hook_timings read coloured output" {
    printf 'check yaml....\033[42mPassed\033[m\n\033[2m- hook id: check-yaml\033[m\n\033[2m- duration: 0.05s\033[m\n\nhook output\n' \
        > "${BATS_TEST_TMPDIR}/run.log"

    run_lib "precommit_display_filter < '${BATS_TEST_TMPDIR}/run.log'"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${output}" = "$(printf 'check yaml....\033[42mPassed\033[m')" ]

    run_lib "precommit_hook_timings '${BATS_TEST_TMPDIR}/run.log'"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${output}" = "check-yaml=0.05s" ]
}

@test "run_precommit_timed returns pre-commit's status, keeps the unfiltered log and filters the display" {
    local _bin="${BATS_TEST_TMPDIR}/bin"
    write_tool "${_bin}" pre-commit "cat '${BATS_TEST_TMPDIR}/run.log'
printf '%s\\n' \"\$*\" > '${BATS_TEST_TMPDIR}/args'
exit 1"
    verbose_fixture "${BATS_TEST_TMPDIR}/run.log"

    # shellcheck disable=SC2016 # intentionally literal, expanded by the inner sh
    run env PATH="${_bin}:${PATH}" sh -c '. "$1"; run_precommit_timed "$2" --config x.yaml' \
        _ "${TIMINGS_LIB}" "${BATS_TEST_TMPDIR}/kept.log"

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [ "$(cat "${BATS_TEST_TMPDIR}/args")" = "run --verbose --color never --config x.yaml" ]
    cmp -s "${BATS_TEST_TMPDIR}/run.log" "${BATS_TEST_TMPDIR}/kept.log"
    [ ! -e "${BATS_TEST_TMPDIR}/kept.log.status" ]
    [[ "${output}" != *"- duration:"* ]]
    [[ "${output}" == *"- exit code: 1"* ]]
}

# ── buildtest phases ──────────────────────────────────────────────────────────

@test "buildtest writes every phase to BUILDTEST_TIMINGS_FILE, with skipped for phases that did not run" {
    local T _bin="${BATS_TEST_TMPDIR}/bin"
    T="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${T}/src" "${BATS_TEST_TMPDIR}/tmp"
    git -C "${T}" init --quiet
    printf 'class Foo { }\n' > "${T}/src/Foo.cs"
    git -C "${T}" add src
    # A repo with no solution runs only cscleanup on its staged .cs file, from
    # a fake dotnet that lists cscleanup as an installed tool.
    write_tool "${_bin}" dotnet "case \"\$1\" in
    --version) printf '11.0.100-rc.3\\n' ;;
    tool) printf 'Package Id    Version    Commands\\ncredfeto.dotnet.repo.formatter    1.0.0    cscleanup\\n' ;;
esac
exit 0"

    cd "${T}" || return 1
    run env -u CLAUDECODE PATH="${_bin}:${TEST_PATH}" TMPDIR="${BATS_TEST_TMPDIR}/tmp" \
        BUILDTEST_TIMINGS_FILE="${BATS_TEST_TMPDIR}/phases" sh "${REPO_DIR}/src/scripts/buildtest"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    grep -qxE 'restore=skipped,format=skipped,cleanup=[0-9]+s,build=skipped,test=skipped,publish=skipped,pack=skipped' \
        "${BATS_TEST_TMPDIR}/phases" || fail_test "unexpected phases: $(cat "${BATS_TEST_TMPDIR}/phases")"
}

# ── commit-msg hook ───────────────────────────────────────────────────────────

# write_timings <repo> <run id> <value>
# Writes a timings file into <repo> as the pre-commit hook would.
write_timings() {
    printf '%s\n%s\n' "$2" "$3" > "$1/.git/precommit-timings"
}

# run_commit_msg <repo> <message file> [run id]
# Runs the commit-msg hook from <repo> on <message file>, as the git process
# whose run id is [run id] (default run-1).
run_commit_msg() {
    run_in_hook_env "$1" "${TEST_PATH}" PRECOMMIT_TIMINGS_RUN_ID_TEST_OVERRIDE="${3:-run-1}" \
        sh "${COMMIT_MSG_HOOK}" "$2"
}

@test "commit-msg adds the trailer and deletes the timings file" {
    local T
    T="$(make_repo)"
    printf 'Subject\n\nBody text.\n' > "${T}/msg"
    write_timings "${T}" run-1 "total=3s check-identity=1s"

    run_commit_msg "${T}" "${T}/msg"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(cat "${T}/msg")" = "$(printf 'Subject\n\nBody text.\n\nPre-commit-Timings: total=3s check-identity=1s')" ]
    [ ! -e "${T}/.git/precommit-timings" ]
}

@test "commit-msg replaces an existing trailer rather than adding a second" {
    local T
    T="$(make_repo)"
    printf 'Subject\n\nPre-commit-Timings: total=9s\n' > "${T}/msg"
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg "${T}" "${T}/msg"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(grep -c '^Pre-commit-Timings:' "${T}/msg")" -eq 1 ]
    grep -qx 'Pre-commit-Timings: total=3s' "${T}/msg"
}

@test "commit-msg leaves the message alone when there is no timings file" {
    local T
    T="$(make_repo)"
    printf 'Subject\n' > "${T}/msg"

    run_commit_msg "${T}" "${T}/msg"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(cat "${T}/msg")" = "Subject" ]
}

@test "commit-msg ignores and deletes a timings file another git process wrote" {
    local T
    T="$(make_repo)"
    printf 'Subject\n' > "${T}/msg"
    write_timings "${T}" run-old "total=3s"

    run_commit_msg "${T}" "${T}/msg" run-new

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(cat "${T}/msg")" = "Subject" ]
    [ ! -e "${T}/.git/precommit-timings" ]
}

@test "commit-msg adds nothing to a message that is empty once comments are removed, so git still aborts" {
    local T
    T="$(make_repo)"
    printf '\n# Please enter the commit message.\n' > "${T}/msg"
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg "${T}" "${T}/msg"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    run ! grep -q 'Pre-commit-Timings' "${T}/msg"
}

@test "commit-msg puts the trailer above git's comments and the git commit -v diff" {
    local T
    T="$(make_repo)"
    cat > "${T}/msg" << 'EOF'
Subject

# Please enter the commit message.
# ------------------------ >8 ------------------------
# Do not modify or remove the line above.
diff --git a/f b/f
+Pre-commit-Timings: not a trailer
EOF
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg "${T}" "${T}/msg"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    # What git keeps: everything above the scissors line, comments removed.
    run sh -c 'sed "/ >8 /,\$d" "$1" | git -C "$2" stripspace --strip-comments' _ "${T}/msg" "${T}"
    [ "${output}" = "$(printf 'Subject\n\nPre-commit-Timings: total=3s')" ] || fail_test "unexpected message: ${output}"
    # The diff below the scissors line is kept as it was.
    tail -n 1 "${T}/msg" | grep -qx '+Pre-commit-Timings: not a trailer'
}

@test "commit-msg adds nothing to a message that starts with the scissors line" {
    local T
    T="$(make_repo)"
    printf '# ------------------------ >8 ------------------------\ndiff --git a/f b/f\n' > "${T}/msg"
    cp "${T}/msg" "${T}/msg.orig"
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg "${T}" "${T}/msg"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    cmp -s "${T}/msg.orig" "${T}/msg" || fail_test "message changed: $(cat "${T}/msg")"
}

# run_commit_msg_with_tool <repo> <command> <body>
# Runs the commit-msg hook as run_commit_msg does, on <repo>/msg, with a
# stand-in <command> running <body> ahead of TEST_PATH.
run_commit_msg_with_tool() {
    local _bin="${BATS_TEST_TMPDIR}/bin"
    write_tool "${_bin}" "$2" "$3"
    run_in_hook_env "$1" "${_bin}:${TEST_PATH}" PRECOMMIT_TIMINGS_RUN_ID_TEST_OVERRIDE=run-1 \
        sh "${COMMIT_MSG_HOOK}" "$1/msg"
}

@test "commit-msg warns and leaves the message alone when it cannot create a temporary directory" {
    local T
    T="$(make_repo)"
    printf 'Subject\n' > "${T}/msg"
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg_with_tool "${T}" mktemp "exit 1"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"could not create a temporary directory"* ]] || fail_test "no warning: ${output}"
    [ "$(cat "${T}/msg")" = "Subject" ]
    [ ! -e "${T}/.git/precommit-timings" ]
}

@test "commit-msg warns and leaves the message alone when git interpret-trailers fails" {
    local T _git
    T="$(make_repo)"
    _git="$(type -P git)"
    printf 'Subject\n' > "${T}/msg"
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg_with_tool "${T}" git "[ \"\$1\" = interpret-trailers ] && exit 1
exec '${_git}' \"\$@\""

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"git interpret-trailers failed"* ]] || fail_test "no warning: ${output}"
    [ "$(cat "${T}/msg")" = "Subject" ]
}

@test "commit-msg warns when it cannot write the commit message" {
    local T
    T="$(make_repo)"
    printf 'Subject\n' > "${T}/msg"
    write_timings "${T}" run-1 "total=3s"

    run_commit_msg_with_tool "${T}" cat "exit 1"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"could not write the commit message"* ]] || fail_test "no warning: ${output}"
    [ "$(cat "${T}/msg")" = "Subject" ]
}

# ── whole commits ─────────────────────────────────────────────────────────────

# make_timed_repo
# Creates a repo whose project pre-commit config runs one trivial hook, with
# a staged file, and prints its path.
make_timed_repo() {
    local _t
    _t="$(make_repo)"
    printf 'repos:
  - repo: local
    hooks:
      - id: always-passes
        name: always passes
        entry: "true"
        language: system
' > "${_t}/.pre-commit-config.yaml"
    printf 'hello\n' > "${_t}/file.txt"
    git -C "${_t}" add .pre-commit-config.yaml file.txt
    printf '%s' "${_t}"
}

# commit_in <repo> <git commit argument>...
# Runs git commit from <repo> with TEST_PATH. Sets $status and $output.
commit_in() {
    local _repo="$1"
    shift
    run_isolated "${_repo}" "${TEST_PATH}" git commit --quiet "$@"
}

# trailer_of <repo>
# Prints the Pre-commit-Timings trailer values of <repo>'s HEAD commit.
trailer_of() {
    git -C "$1" log -1 --format='%(trailers:key=Pre-commit-Timings,valueonly)'
}

@test "a commit through the hooks gets one trailer timing every step and pre-commit hook" {
    command -v pre-commit > /dev/null 2>&1 || skip "pre-commit not installed"
    local T
    T="$(make_timed_repo)"

    commit_in "${T}" -m "Add file"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(git -C "${T}" log -1 --format=%B | grep -c '^Pre-commit-Timings:')" -eq 1 ]
    local _value
    _value="$(trailer_of "${T}" | sed '/^$/d')"
    [[ "${_value}" =~ ^total=[0-9]+s\ check-identity=[0-9]+s\ check-merge-commits=[0-9]+s\ check-ignored-files=[0-9]+s\ check-funfair-props=[0-9]+s\ clean-package-lock-registry=[0-9]+s\ pre-commit=[0-9]+s\(always-passes=[0-9.]+s\)\ check-changelog=skipped\  ]] \
        || fail_test "unexpected trailer: ${_value}"
    [[ "${_value}" == *" cfn-lint=skipped" ]]
    [ ! -e "${T}/.git/precommit-timings" ]
    # pre-commit's own display is unchanged by --verbose.
    [[ "${output}" != *"- duration:"* ]]
}

@test "amending a commit through the hooks replaces its trailer" {
    command -v pre-commit > /dev/null 2>&1 || skip "pre-commit not installed"
    local T
    T="$(make_timed_repo)"
    commit_in "${T}" -m "Add file"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    printf 'more\n' >> "${T}/file.txt"
    git -C "${T}" add file.txt

    commit_in "${T}" --amend --no-edit

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(git -C "${T}" log -1 --format=%B | grep -c '^Pre-commit-Timings:')" -eq 1 ]
}

@test "a commit with --no-verify gets no trailer" {
    local T
    T="$(make_timed_repo)"

    commit_in "${T}" --no-verify -m "Add file"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(trailer_of "${T}" | sed '/^$/d')" ]
}

@test "a timings file left by an aborted commit does not reach a --no-verify commit" {
    local T
    T="$(make_timed_repo)"
    write_timings "${T}" "1:1" "total=3s"

    commit_in "${T}" --no-verify -m "Add file"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(trailer_of "${T}" | sed '/^$/d')" ]
}

@test "a commit with an empty message still aborts" {
    command -v pre-commit > /dev/null 2>&1 || skip "pre-commit not installed"
    local T
    T="$(make_timed_repo)"

    commit_in "${T}" -m ""

    [ "${status}" -ne 0 ] || fail_with_run_output "${status}" "${output}" "non-zero"
    run git -C "${T}" rev-parse --verify --quiet HEAD
    [ "${status}" -ne 0 ]
}

@test "the hook writes no timings file in --all-files mode" {
    command -v pre-commit > /dev/null 2>&1 || skip "pre-commit not installed"
    local T
    T="$(make_timed_repo)"
    commit_without_hooks "${T}" .

    run_hook_all_files "${T}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ ! -e "${T}/.git/precommit-timings" ]
}
