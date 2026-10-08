#!/usr/bin/env bats
# Acceptance tests for the --system path of install: the system git config it
# writes through sudo must end up world-readable (0644) even when the caller's
# umask is restrictive, because sudo keeps that umask.
#
# Never runs the real installer or real sudo: install is copied into a temp
# tree with stub dependency/setup scripts, and sudo and git are fakes on PATH
# that write to a temp stand-in for the system config. The stand-in's
# directory name holds a double quote and a backslash, which real git would
# C-quote in --show-origin output without -z, plus a space.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    STAGE="${BATS_TEST_TMPDIR}/stage"
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    FAKE_ETC_DIR="${BATS_TEST_TMPDIR}/etc \"dir\"\\x"
    mkdir -p "${STAGE}" "${BATS_TEST_TMPDIR}/home" "${FAKE_ETC_DIR}"

    cp "${REPO_DIR}/install" "${STAGE}/install"
    cp -R "${REPO_DIR}/src" "${STAGE}/src"
    for _stub in install-deps-arch install-deps-debian check-setup acceptance-test; do
        printf '#!/bin/sh\nexit 0\n' > "${STAGE}/${_stub}"
        chmod +x "${STAGE}/${_stub}"
    done

    write_fake_sudo "${FAKE_BIN}"

    cat > "${FAKE_BIN}/git" <<'EOF'
#!/bin/sh
case "$*" in
    "config --global --get core.hooksPath")
        exit 1
        ;;
    "config --system --show-origin -z --get core.hooksPath")
        [ -z "${FAKE_GIT_FAIL_ORIGIN:-}" ] || exit 1
        printf 'file:%s\0%s\0' "$FAKE_SYSTEM_GITCONFIG" "$(cat "$FAKE_SYSTEM_GITCONFIG")"
        ;;
    "config --system core.hooksPath "*)
        [ -z "${FAKE_GIT_FAIL_WRITE:-}" ] || exit 1
        printf '%s' "$4" > "$FAKE_SYSTEM_GITCONFIG"
        ;;
    *)
        printf 'fake git: unexpected arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "${FAKE_BIN}/git"

    export FAKE_SYSTEM_GITCONFIG="${FAKE_ETC_DIR}/gitconfig"
}

run_system_install() {
    umask 027
    run env HOME="${BATS_TEST_TMPDIR}/home" PATH="${FAKE_BIN}:${TEST_PATH}" "${STAGE}/install" --system
}

@test "system install creates the system git config world-readable under umask 027" {
    run_system_install

    [ "${status}" -eq 0 ]
    [ "$(stat -c %a "${FAKE_SYSTEM_GITCONFIG}")" = "644" ]
    [ "$(cat "${FAKE_SYSTEM_GITCONFIG}")" = "${STAGE}/src/hooks" ]
}

@test "system install repairs an existing system git config that is not world-readable" {
    printf 'stale' > "${FAKE_SYSTEM_GITCONFIG}"
    chmod 0640 "${FAKE_SYSTEM_GITCONFIG}"

    run_system_install

    [ "${status}" -eq 0 ]
    [ "$(stat -c %a "${FAKE_SYSTEM_GITCONFIG}")" = "644" ]
}

@test "system install dies when writing the system git config fails" {
    export FAKE_GIT_FAIL_WRITE=1

    run_system_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to set core.hooksPath in the system git config"* ]]
}

@test "system install dies when the system git config cannot be located" {
    export FAKE_GIT_FAIL_ORIGIN=1

    run_system_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to locate the system git config"* ]]
}

@test "system install dies when making the system git config world-readable fails" {
    export FAKE_SUDO_FAIL_COMMAND=chmod

    run_system_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (${FAKE_SYSTEM_GITCONFIG}) world-readable"* ]]
}
