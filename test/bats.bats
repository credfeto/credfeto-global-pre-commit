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
    run bash -c 'cd "$1" && "$2"' _ "${T}" "${REPO_DIR}/src/scripts/run-bats"

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
