#!/usr/bin/env bats
# Acceptance tests for the --system path of install: the system git config it
# writes through sudo must end up world-readable (0644) even when the caller's
# umask is restrictive, because sudo keeps that umask.
#
# Never runs the real installer or real sudo: install is copied into a temp
# tree with stub dependency/setup scripts, and sudo and git are fakes on PATH
# that write to a temp stand-in for the system config.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    STAGE="${BATS_TEST_TMPDIR}/stage"
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${STAGE}" "${FAKE_BIN}" "${BATS_TEST_TMPDIR}/home" "${BATS_TEST_TMPDIR}/etc dir"

    cp "${REPO_DIR}/install" "${STAGE}/install"
    cp -R "${REPO_DIR}/src" "${STAGE}/src"
    for _stub in install-deps-arch install-deps-debian check-setup acceptance-test; do
        printf '#!/bin/sh\nexit 0\n' > "${STAGE}/${_stub}"
        chmod +x "${STAGE}/${_stub}"
    done

    cat > "${FAKE_BIN}/sudo" <<'EOF'
#!/bin/sh
if [ "$1" = chmod ] && [ -n "${FAKE_SUDO_FAIL_CHMOD:-}" ]; then
    exit 1
fi
exec "$@"
EOF

    cat > "${FAKE_BIN}/git" <<'EOF'
#!/bin/sh
case "$*" in
    "config --global --get core.hooksPath")
        exit 1
        ;;
    "config --system --show-origin --get core.hooksPath")
        printf 'file:%s\t%s\n' "$FAKE_SYSTEM_GITCONFIG" "$(cat "$FAKE_SYSTEM_GITCONFIG")"
        ;;
    "config --system core.hooksPath "*)
        [ -z "${FAKE_GIT_FAIL_WRITE:-}" ] || exit 1
        umask > "$FAKE_WRITE_UMASK"
        printf '%s' "$4" > "$FAKE_SYSTEM_GITCONFIG"
        ;;
    *)
        printf 'fake git: unexpected arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "${FAKE_BIN}/sudo" "${FAKE_BIN}/git"

    export FAKE_SYSTEM_GITCONFIG="${BATS_TEST_TMPDIR}/etc dir/gitconfig"
    export FAKE_WRITE_UMASK="${BATS_TEST_TMPDIR}/write-umask"
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
    [ "$(cat "${FAKE_WRITE_UMASK}")" = "0022" ]
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

@test "system install dies when making the system git config world-readable fails" {
    export FAKE_SUDO_FAIL_CHMOD=1

    run_system_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (${FAKE_SYSTEM_GITCONFIG}) world-readable"* ]]
}
