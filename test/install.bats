#!/usr/bin/env bats
# Acceptance tests for the --system path of install: the system git config it
# writes through sudo must end up world-readable (0644) even when the caller's
# umask is restrictive, because sudo keeps that umask, and one an earlier
# install left unreadable must be repaired before the dependency step, which
# runs git as the user.
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
    for _stub in check-setup acceptance-test; do
        printf '#!/bin/sh\nexit 0\n' > "${STAGE}/${_stub}"
        chmod +x "${STAGE}/${_stub}"
    done
    # The real dependency step runs git as the user (paru/yay, the nvm
    # installer), so the stub does too and records that git worked.
    for _stub in install-deps-arch install-deps-debian; do
        cat > "${STAGE}/${_stub}" <<'EOF'
#!/bin/sh
git config --get user.name > /dev/null
[ $? -le 1 ] || exit 1
: > "$FAKE_DEPS_RAN_MARKER"
EOF
        chmod +x "${STAGE}/${_stub}"
    done

    write_fake_sudo "${FAKE_BIN}"

    # Models how real git reads the system config: the test user owns the
    # stand-in, so a non-root read is judged by its "other" read bit, as it
    # would be for a root-owned file.
    cat > "${FAKE_BIN}/git" <<'EOF'
#!/bin/sh
system_config_unreadable() {
    [ -e "$FAKE_SYSTEM_GITCONFIG" ] && [ -z "${FAKE_SUDO_AS_ROOT:-}" ] || return 1
    case "$(stat -c %a "$FAKE_SYSTEM_GITCONFIG")" in
        *[4-7]) return 1 ;;
    esac
    printf "fatal: unable to access '%s': Permission denied\n" "$FAKE_SYSTEM_GITCONFIG" >&2
}
case "$*" in
    "config --global --get core.hooksPath")
        exit 1
        ;;
    "config --get user.name")
        ! system_config_unreadable || exit 128
        exit 1
        ;;
    "config --system --list")
        [ -e "$FAKE_SYSTEM_GITCONFIG" ] || exit 128
        ! system_config_unreadable || exit 128
        printf 'core.hookspath=%s\n' "$(cat "$FAKE_SYSTEM_GITCONFIG")"
        ;;
    "config --system --show-origin -z --list")
        [ -z "${FAKE_GIT_FAIL_ORIGIN:-}" ] || exit 1
        [ -e "$FAKE_SYSTEM_GITCONFIG" ] || exit 128
        ! system_config_unreadable || exit 128
        printf 'file:%s\0core.hookspath\n%s\0' "$FAKE_SYSTEM_GITCONFIG" "$(cat "$FAKE_SYSTEM_GITCONFIG")"
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
    export FAKE_DEPS_RAN_MARKER="${BATS_TEST_TMPDIR}/deps-ran"
}

# run_system_install [NAME=value ...]
# Each NAME=value is set in the installer's environment, so a test can make a
# fake fail without exporting into its own shell.
run_system_install() {
    umask 027
    run env HOME="${BATS_TEST_TMPDIR}/home" PATH="${FAKE_BIN}:${TEST_PATH}" "$@" "${STAGE}/install" --system
}

@test "system install creates the system git config world-readable under umask 027" {
    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(stat -c %a "${FAKE_SYSTEM_GITCONFIG}")" = "644" ]
    [ "$(cat "${FAKE_SYSTEM_GITCONFIG}")" = "${STAGE}/src/hooks" ]
}

@test "system install repairs an unreadable system git config before the dependency step runs git" {
    printf 'stale' > "${FAKE_SYSTEM_GITCONFIG}"
    chmod 0640 "${FAKE_SYSTEM_GITCONFIG}"

    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(stat -c %a "${FAKE_SYSTEM_GITCONFIG}")" = "644" ]
    [ "$(cat "${FAKE_SYSTEM_GITCONFIG}")" = "${STAGE}/src/hooks" ]
}

@test "system install dies before the dependency step when an unreadable system git config cannot be repaired" {
    printf 'stale' > "${FAKE_SYSTEM_GITCONFIG}"
    chmod 0640 "${FAKE_SYSTEM_GITCONFIG}"

    run_system_install FAKE_SUDO_FAIL_COMMAND=chmod

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (${FAKE_SYSTEM_GITCONFIG}) world-readable"* ]]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(cat "${FAKE_SYSTEM_GITCONFIG}")" = "stale" ]
}

@test "system install dies when writing the system git config fails" {
    run_system_install FAKE_GIT_FAIL_WRITE=1

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to set core.hooksPath in the system git config"* ]]
}

@test "system install dies when the system git config cannot be located" {
    run_system_install FAKE_GIT_FAIL_ORIGIN=1

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to locate the system git config"* ]]
}

@test "system install dies when making the system git config world-readable fails" {
    run_system_install FAKE_SUDO_FAIL_COMMAND=chmod

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (${FAKE_SYSTEM_GITCONFIG}) world-readable"* ]]
}
