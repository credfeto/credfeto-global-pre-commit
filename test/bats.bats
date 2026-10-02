#!/usr/bin/env bats
# Acceptance tests for the bats pre-commit hook.
# Verifies that a failing bats test blocks the commit and a passing one allows it.

load test_helper

# ── bats ─────────────────────────────────────────────────────────────────────

@test "failing bats test blocks commit" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/failing-bats-test)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "always fails" {\n  false\n}\n' > "${T}/test/fail.bats"
    git -C "${T}" add .pre-commit-config.yaml test/fail.bats
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "passing bats tests allow commit" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/passing-bats-test)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "always passes" {\n  true\n}\n' > "${T}/test/pass.bats"
    git -C "${T}" add .pre-commit-config.yaml test/pass.bats
    run_hook "${T}"
    if [ "${status}" -ne 0 ]; then
        printf '# hook exit status: %s\n' "${status}" >&3
        printf '# hook output:\n' >&3
        printf '%s\n' "${output}" | sed 's/^/# /' >&3
    fi
    [ "${status}" -eq 0 ]
}

@test "run-bats pins its tmpdir under /tmp regardless of ambient TMPDIR" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/tmpdir-location)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    # shellcheck disable=SC2016 # $BATS_TMPDIR is meant literally here — it's written
    # into the generated bats file below and only expands when that file runs.
    printf '#!/usr/bin/env bats\n@test "dump tmpdir" {\n  printf "%%s\\n" "$BATS_TMPDIR" > "%s/tmpdir-used.txt"\n  false\n}\n' "${T}" > "${T}/test/dump.bats"
    git -C "${T}" add .pre-commit-config.yaml test/dump.bats

    local _fake_tmpdir="${BATS_TEST_TMPDIR}/not-tmp"
    mkdir -p "${_fake_tmpdir}"
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR XDG_RUNTIME_DIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" TMPDIR="$3" sh "$4"
    ' _ "${T}" "${TEST_PATH}" "${_fake_tmpdir}" "${HOOK}"

    [ "${status}" -eq 1 ]
    run cat "${T}/tmpdir-used.txt"
    [ "${output}" = "/tmp" ]
}

@test "run-bats uses XDG_RUNTIME_DIR/<owner>/<repo>/bats for a remote-tracked repo" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG _fake_xdg
    T="$(make_repo feature/xdg-remote)"
    git -C "${T}" remote add origin "git@github.com:acme/widget.git"
    # Deliberately short and flat, like a real XDG_RUNTIME_DIR (e.g.
    # /run/user/1000) — not nested under BATS_TEST_TMPDIR, which would make it
    # unrealistically long and risk tripping the #169 length safety net below.
    _fake_xdg="$(mktemp -d /tmp/xdg.XXXXXX)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    # shellcheck disable=SC2016 # $BATS_TMPDIR is meant literally here — it's written
    # into the generated bats file below and only expands when that file runs.
    printf '#!/usr/bin/env bats\n@test "dump tmpdir" {\n  printf "%%s\\n" "$BATS_TMPDIR" > "%s/tmpdir-used.txt"\n  false\n}\n' "${T}" > "${T}/test/dump.bats"
    git -C "${T}" add .pre-commit-config.yaml test/dump.bats

    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" XDG_RUNTIME_DIR="$3" sh "$4"
    ' _ "${T}" "${TEST_PATH}" "${_fake_xdg}" "${HOOK}"

    [ "${status}" -eq 1 ]
    run cat "${T}/tmpdir-used.txt"
    [ "${output}" = "${_fake_xdg}/acme/widget/bats" ]
    rm -rf "${_fake_xdg}"
}

@test "run-bats uses XDG_RUNTIME_DIR/_local/<basename>/bats for a local-only repo" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG _fake_xdg
    T="$(make_repo feature/xdg-local)"
    # Deliberately short and flat, like a real XDG_RUNTIME_DIR (e.g.
    # /run/user/1000) — not nested under BATS_TEST_TMPDIR, which would make it
    # unrealistically long and risk tripping the #169 length safety net below.
    _fake_xdg="$(mktemp -d /tmp/xdg.XXXXXX)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    # shellcheck disable=SC2016 # $BATS_TMPDIR is meant literally here — it's written
    # into the generated bats file below and only expands when that file runs.
    printf '#!/usr/bin/env bats\n@test "dump tmpdir" {\n  printf "%%s\\n" "$BATS_TMPDIR" > "%s/tmpdir-used.txt"\n  false\n}\n' "${T}" > "${T}/test/dump.bats"
    git -C "${T}" add .pre-commit-config.yaml test/dump.bats

    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" XDG_RUNTIME_DIR="$3" sh "$4"
    ' _ "${T}" "${TEST_PATH}" "${_fake_xdg}" "${HOOK}"

    [ "${status}" -eq 1 ]
    run cat "${T}/tmpdir-used.txt"
    [ "${output}" = "${_fake_xdg}/_local/repo/bats" ]
    rm -rf "${_fake_xdg}"
}

@test "run-bats falls back to /tmp when the resolved XDG_RUNTIME_DIR path would be too long for AF_UNIX sun_path" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG _fake_xdg
    T="$(make_repo feature/xdg-too-long)"
    # A realistic-length owner/repo pair (matches the credfeto/credfeto-orchestrator
    # case from #169) combined with a short, realistic XDG_RUNTIME_DIR is enough
    # to exceed the reserved AF_UNIX headroom on its own.
    git -C "${T}" remote add origin "git@github.com:credfeto/credfeto-orchestrator.git"
    _fake_xdg="$(mktemp -d /tmp/xdg.XXXXXX)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    # shellcheck disable=SC2016 # $BATS_TMPDIR is meant literally here — it's written
    # into the generated bats file below and only expands when that file runs.
    printf '#!/usr/bin/env bats\n@test "dump tmpdir" {\n  printf "%%s\\n" "$BATS_TMPDIR" > "%s/tmpdir-used.txt"\n  false\n}\n' "${T}" > "${T}/test/dump.bats"
    git -C "${T}" add .pre-commit-config.yaml test/dump.bats

    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        env PATH="$2" XDG_RUNTIME_DIR="$3" sh "$4"
    ' _ "${T}" "${TEST_PATH}" "${_fake_xdg}" "${HOOK}"

    [ "${status}" -eq 1 ]
    run cat "${T}/tmpdir-used.txt"
    [ "${output}" = "/tmp" ]
    rm -rf "${_fake_xdg}"
}

@test "run-bats sweeps bats-run-* dirs under /tmp older than 60 minutes, leaving fresh ones alone" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    local _stale="/tmp/bats-run-staletest-$$"
    local _fresh="/tmp/bats-run-freshtest-$$"
    mkdir -p "${_stale}" "${_fresh}"
    touch -d "2 hours ago" "${_stale}"

    local T
    T="$(make_repo feature/sweep-test)"
    # The sweep runs only once run-bats is going to run the suite, so the
    # fixture needs a bats suite for run-bats to get that far.
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "always passes" {\n  true\n}\n' > "${T}/test/pass.bats"
    # Isolated so the inner suite runs under its own /tmp/bats-run-XXXXXX
    # rather than wiping the XDG_RUNTIME_DIR path concurrent tests share.
    run_isolated "${T}" "${TEST_PATH}" "${REPO_DIR}/src/scripts/run-bats"

    [ ! -d "${_stale}" ]
    [ -d "${_fresh}" ]
    rm -rf "${_fresh}"
}

@test "bats hook passes when no test directory exists" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG
    T="$(make_repo feature/no-test-dir-bats)"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '#!/usr/bin/env bats\n@test "stub" {\n  true\n}\n' > "${T}/stub.bats"
    git -C "${T}" add .pre-commit-config.yaml stub.bats
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}

@test "bare-name run-bats wrapper resolves when scripts dir is not on the ambient PATH" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T BATS_HOOK_CONFIG _stripped_path
    T="$(make_repo feature/bare-name-path-test)"
    # Reproduces #173: entry is a bare command name (as in the real
    # src/.pre-commit-config.yaml), and PATH is stripped of every directory
    # that could resolve it (the repo's own src/scripts, and any install
    # symlink dir such as ~/.local/bin) — only the hook's own PATH= prepend
    # can make this resolve.
    _stripped_path="$(printf '%s' "${TEST_PATH}" | tr ':' '\n' \
        | grep -Fxv "${REPO_DIR}/src/scripts" \
        | grep -Fxv "${HOME}/.local/bin" \
        | tr '\n' ':' | sed 's/:$//')"
    BATS_HOOK_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: run-bats
        language: system
        pass_filenames: false
        files: \\.bats\$
"
    printf '%s' "${BATS_HOOK_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "always passes" {\n  true\n}\n' > "${T}/test/pass.bats"
    git -C "${T}" add .pre-commit-config.yaml test/pass.bats
    run_hook_env "${T}" "${_stripped_path}" "${BATS_TEST_TMPDIR}/xdg-cache"
    if [ "${status}" -ne 0 ]; then
        printf '# hook exit status: %s\n' "${status}" >&3
        printf '# hook output:\n' >&3
        printf '%s\n' "${output}" | sed 's/^/# /' >&3
    fi
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"not found"* ]]
}

# ── run-bats trigger ─────────────────────────────────────────────────────────
# Mirrors the production bats hook (no files: filter; run-bats decides from
# the staged filenames whether to run), with a full-path entry so it does not
# depend on PATH.
BATS_TRIGGER_CONFIG="repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: ${REPO_DIR}/src/scripts/run-bats
        language: system
        types: [text]
        pass_filenames: true
        require_serial: true
"

# make_trigger_repo <branch> <suite result: true|false>
# Creates a fixture repo with BATS_TRIGGER_CONFIG and a one-test suite that
# passes or fails, both committed so that neither is a staged file: a staged
# .bats file qualifies on its own and would make every trigger test vacuous.
make_trigger_repo() {
    local _t
    _t="$(make_repo "$1")"
    printf '%s' "${BATS_TRIGGER_CONFIG}" > "${_t}/.pre-commit-config.yaml"
    mkdir -p "${_t}/test"
    printf '#!/usr/bin/env bats\n@test "fixture" {\n  %s\n}\n' "$2" > "${_t}/test/fixture.bats"
    commit_without_hooks "${_t}" . > /dev/null
    printf '%s' "${_t}"
}

# run_isolated <cwd> <path> <command>...
# Runs <command> from <cwd> with PATH set to <path>, outside this bats run's
# own environment. XDG_RUNTIME_DIR is unset because every fixture repo
# resolves to the same $XDG_RUNTIME_DIR/_local/repo/bats, which run-bats
# wipes before each run; under bats --jobs that would delete a concurrent
# test's tmpdir, while the /tmp fallback gives each run its own
# bats-run-XXXXXX.
run_isolated() {
    run bash -c '
        cd "$1"
        unset CLAUDECODE BATS_RUN_TMPDIR BATS_SUITE_TMPDIR BATS_FILE_TMPDIR BATS_TEST_TMPDIR XDG_RUNTIME_DIR
        bats_readlinkf() { readlink -f "$1"; }
        export -f bats_readlinkf
        _path="$2"
        shift 2
        env PATH="${_path}" "$@"
    ' _ "$@"
}

# run_bats_hook <repo> [path]
# Runs only the bats hook through pre-commit against the repo's staged files,
# bypassing the always-on stages of src/hooks/pre-commit that these tests do
# not need. --verbose shows the hook's output even when it passes, so a test
# can tell a suite that ran and passed from one that never ran.
run_bats_hook() {
    run_isolated "$1" "${2:-${TEST_PATH}}" pre-commit run bats --verbose
}

# The assertion helpers below take the last run's status and output as
# arguments ("${status}" "${output}") rather than reading bats' run variables
# directly, which shellcheck cannot follow out of a @test (SC2030/SC2031).

# fail_with_run_output <status> <output> <expected status>
# Prints a run's exit status and output to the TAP stream, so an unexpected
# result is diagnosable, and fails.
fail_with_run_output() {
    printf '# exit status: %s (expected %s)\n# output:\n' "$1" "$3" >&3
    printf '%s\n' "$2" | sed 's/^/# /' >&3
    return 1
}

# assert_fixture_failed / assert_fixture_passed / assert_fixture_not_run
#   <status> <output>
# Check a run's exit status and the fixture suite's own TAP line, so a hook
# that failed for any other reason, or passed without running, is not
# mistaken for the suite having run. Each is a single && chain rather than
# relying on set -e, which bats suspends when a caller uses the helper in an
# || list.
assert_fixture_failed() {
    { [ "$1" -eq 1 ] && [[ "$2" == *"not ok 1 fixture"* ]]; } ||
        fail_with_run_output "$1" "$2" 1
}

assert_fixture_passed() {
    { [ "$1" -eq 0 ] &&
        [[ "$2" == *"ok 1 fixture"* ]] &&
        [[ "$2" != *"not ok 1 fixture"* ]]; } ||
        fail_with_run_output "$1" "$2" 0
}

assert_fixture_not_run() {
    { [ "$1" -eq 0 ] && [[ "$2" != *"1 fixture"* ]]; } ||
        fail_with_run_output "$1" "$2" 0
}

# make_recording_bats_shim
# Creates a bats shim that records being called (in $BATS_TEST_TMPDIR/
# bats-was-run) and fails, and prints the directory holding it. Put first on
# PATH, it proves run-bats never invokes bats: a call would show as both the
# marker file and exit 1.
make_recording_bats_shim() {
    local _shim_dir="${BATS_TEST_TMPDIR}/shim"
    mkdir -p "${_shim_dir}"
    printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "${BATS_TEST_TMPDIR}/bats-was-run" > "${_shim_dir}/bats"
    chmod +x "${_shim_dir}/bats"
    printf '%s' "${_shim_dir}"
}

# assert_bats_not_invoked <status> <output>
assert_bats_not_invoked() {
    { [ "$1" -eq 0 ] && [ ! -e "${BATS_TEST_TMPDIR}/bats-was-run" ]; } ||
        fail_with_run_output "$1" "$2" 0
}

skip_unless_bats_and_pre_commit() {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
}

@test "staged shell script with no .bats file runs a failing suite and blocks the commit" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-script-fails false)"
    printf '#!/bin/sh\necho hello\n' > "${T}/script.sh"
    git -C "${T}" add script.sh
    run_bats_hook "${T}"
    assert_fixture_failed "${status}" "${output}"
}

@test "staged shell script with no .bats file runs a passing suite and allows the commit" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-script-passes true)"
    printf '#!/bin/sh\necho hello\n' > "${T}/script.sh"
    git -C "${T}" add script.sh
    run_bats_hook "${T}"
    assert_fixture_passed "${status}" "${output}"
}

@test "staged README.md alone does not run a failing suite" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-readme false)"
    printf '# Title\n' > "${T}/README.md"
    git -C "${T}" add README.md
    run_bats_hook "${T}"
    assert_fixture_not_run "${status}" "${output}"
}

@test "staged test/test_helper.bash runs the suite" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-test-helper false)"
    printf 'helper() { true; }\n' > "${T}/test/test_helper.bash"
    git -C "${T}" add test/test_helper.bash
    run_bats_hook "${T}"
    assert_fixture_failed "${status}" "${output}"
}

@test "staged src/.pre-commit-config.yaml runs the suite" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-src-pre-commit-config false)"
    mkdir -p "${T}/src"
    printf 'repos: []\n' > "${T}/src/.pre-commit-config.yaml"
    git -C "${T}" add src/.pre-commit-config.yaml
    run_bats_hook "${T}"
    assert_fixture_failed "${status}" "${output}"
}

@test "staged extensionless file with a shellcheck shell=bash first line runs the suite" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-shellcheck-directive false)"
    printf '# shellcheck shell=bash\nhelper() { true; }\n' > "${T}/library"
    git -C "${T}" add library
    run_bats_hook "${T}"
    assert_fixture_failed "${status}" "${output}"
}

@test "staged extensionless files with env -S bash and /usr/local/bin/bash shebangs each run the suite" {
    skip_unless_bats_and_pre_commit
    local T shebang
    T="$(make_trigger_repo feature/trigger-shebangs false)"
    for shebang in '#!/usr/bin/env -S bash' '#!/usr/local/bin/bash'; do
        printf '%s\necho hello\n' "${shebang}" > "${T}/tool"
        git -C "${T}" add tool
        run_bats_hook "${T}"
        assert_fixture_failed "${status}" "${output}" || { printf '# shebang: %s\n' "${shebang}" >&3; return 1; }
        git -C "${T}" rm --cached --quiet tool
    done
}

@test "staged extensionless file with an env python3 shebang does not run a failing suite" {
    skip_unless_bats_and_pre_commit
    local T
    T="$(make_trigger_repo feature/trigger-python-shebang false)"
    printf '#!/usr/bin/env python3\nprint("hello")\n' > "${T}/tool"
    git -C "${T}" add tool
    run_bats_hook "${T}"
    assert_fixture_not_run "${status}" "${output}"
}

@test "staged shell script with a test directory holding no .bats file exits 0 without running bats" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T _shim_dir
    T="$(make_repo feature/trigger-no-bats-files)"
    printf '%s' "${BATS_TRIGGER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf 'not a bats suite\n' > "${T}/test/notes.txt"
    commit_without_hooks "${T}" . > /dev/null
    _shim_dir="$(make_recording_bats_shim)"
    printf '#!/bin/sh\necho hello\n' > "${T}/script.sh"
    git -C "${T}" add script.sh
    run_bats_hook "${T}" "${_shim_dir}:${TEST_PATH}"
    assert_bats_not_invoked "${status}" "${output}"
}

@test "production bats hook passes every staged text file serially with no files filter" {
    local _hook
    _hook="$(sed -n '/^ *- id: bats$/,/^$/p' "${REPO_DIR}/src/.pre-commit-config.yaml")"
    [ -n "${_hook}" ]
    printf '%s\n' "${_hook}" | grep -Eq '^ +types: \[text\]$'
    printf '%s\n' "${_hook}" | grep -Eq '^ +pass_filenames: true$'
    printf '%s\n' "${_hook}" | grep -Eq '^ +require_serial: true$'
    run grep -Eq '^ +files:' <<< "${_hook}"
    [ "${status}" -eq 1 ]
}

# ── run-bats --all-files ─────────────────────────────────────────────────────
# pre-commit passes filenames even in --all-files mode, so the --all-files
# argument is only reachable by calling run-bats directly.

# run_bats_all_files <cwd> [path]
# Runs run-bats --all-files from <cwd>, isolated as for run_bats_hook.
run_bats_all_files() {
    run_isolated "$1" "${2:-${TEST_PATH}}" "${REPO_DIR}/src/scripts/run-bats" --all-files
}

# The suite is left untracked in both tests: a tracked .bats file qualifies on
# its own, so tracking it would make the positive test vacuous and the
# negative one impossible.

@test "run-bats --all-files from a subdirectory runs the suite when a tracked extensionless shell script qualifies" {
    if ! command -v bats > /dev/null 2>&1; then
        skip "bats not installed"
    fi
    local T
    T="$(make_repo feature/all-files-qualifies)"
    mkdir -p "${T}/test" "${T}/docs"
    printf '#!/usr/bin/env bats\n@test "fixture" {\n  false\n}\n' > "${T}/test/fixture.bats"
    printf '#!/bin/sh\necho hello\n' > "${T}/tool"
    printf '# Docs\n' > "${T}/docs/index.md"
    commit_without_hooks "${T}" tool > /dev/null
    commit_without_hooks "${T}" docs/index.md > /dev/null
    run_bats_all_files "${T}/docs"
    assert_fixture_failed "${status}" "${output}"
}

@test "run-bats --all-files exits 0 without running bats when no tracked file qualifies" {
    local T _shim_dir
    T="$(make_repo feature/all-files-no-qualifier)"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "fixture" {\n  false\n}\n' > "${T}/test/fixture.bats"
    printf '# Title\n' > "${T}/README.md"
    commit_without_hooks "${T}" README.md > /dev/null
    _shim_dir="$(make_recording_bats_shim)"
    run_bats_all_files "${T}" "${_shim_dir}:${TEST_PATH}"
    assert_bats_not_invoked "${status}" "${output}"
}
