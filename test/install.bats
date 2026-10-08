#!/usr/bin/env bats
# Acceptance tests for the --system path of install: the system git config it
# writes through sudo must end up readable by every user even when the caller's
# umask is restrictive, because sudo keeps that umask, and one an earlier
# install left unreadable must be repaired before the dependency step, which
# runs git as the user. Only read bits are added, so other mode bits an admin
# chose are kept.
#
# Never runs the real installer or real sudo: install is copied into a temp
# tree with stub dependency/setup scripts, and sudo and git are fakes on PATH
# that write to a temp stand-in for the system config. The stand-in's
# directory name holds a double quote, a backslash and a space, so a path that
# is quoted or has its backslashes interpreted on the way back from git fails.
# The host's distro never matters: a stand-in os-release names Arch.

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
    # would be for a root-owned file. var GIT_CONFIG_SYSTEM prints the path
    # whether or not the file exists, as git 2.42+ does, or with
    # FAKE_GIT_FAIL_VAR set rejects the variable with exit 129, as older git
    # does.
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
        cat "$FAKE_SYSTEM_GITCONFIG"
        ;;
    "-C / var GIT_CONFIG_SYSTEM")
        if [ -n "${FAKE_GIT_FAIL_VAR:-}" ]; then
            printf 'usage: git var (-l | <variable>)\n' >&2
            exit 129
        fi
        printf '%s\n' "$FAKE_SYSTEM_GITCONFIG"
        ;;
    "config --system core.hooksPath "*)
        [ -z "${FAKE_GIT_FAIL_WRITE:-}" ] || exit 1
        printf '[core]\n\thooksPath = %s\n' "$4" > "$FAKE_SYSTEM_GITCONFIG"
        ;;
    *)
        printf 'fake git: unexpected arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "${FAKE_BIN}/git"

    FAKE_OS_RELEASE="${BATS_TEST_TMPDIR}/os-release"
    printf 'ID=arch\n' > "${FAKE_OS_RELEASE}"

    export FAKE_SYSTEM_GITCONFIG="${FAKE_ETC_DIR}/gitconfig"
    export FAKE_DEPS_RAN_MARKER="${BATS_TEST_TMPDIR}/deps-ran"
}

# run_system_install [NAME=value ...]
# Each NAME=value is set in the installer's environment, so a test can make a
# fake fail without exporting into its own shell.
run_system_install() {
    umask 027
    run env HOME="${BATS_TEST_TMPDIR}/home" PATH="${FAKE_BIN}:${TEST_PATH}" \
        OS_RELEASE_TEST_OVERRIDE="${FAKE_OS_RELEASE}" "$@" "${STAGE}/install" --system
}

# Writes the stand-in system config with the given content and mode.
write_system_config() {
    printf '%s' "$1" > "${FAKE_SYSTEM_GITCONFIG}"
    chmod "$2" "${FAKE_SYSTEM_GITCONFIG}"
}

system_config_mode() {
    stat -c %a "${FAKE_SYSTEM_GITCONFIG}"
}

system_config_has_hooks_path() {
    grep -Fq "hooksPath = ${STAGE}/src/hooks" "${FAKE_SYSTEM_GITCONFIG}"
}

@test "system install creates the system git config world-readable under umask 027" {
    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
    system_config_has_hooks_path
}

@test "system install repairs an unreadable system git config before the dependency step runs git" {
    write_system_config 'stale' 0640

    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
    system_config_has_hooks_path
}

@test "system install repairs an unreadable system git config that has no entries" {
    write_system_config '[core]
' 0640

    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
    system_config_has_hooks_path
}

@test "system install only adds read bits, keeping a group-writable mode an admin chose" {
    write_system_config 'stale' 0660

    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "664" ]
    system_config_has_hooks_path
}

@test "system install dies before the dependency step when an unreadable system git config cannot be repaired" {
    write_system_config 'stale' 0640

    run_system_install FAKE_SUDO_FAIL_COMMAND=chmod

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (${FAKE_SYSTEM_GITCONFIG}) world-readable"* ]]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(cat "${FAKE_SYSTEM_GITCONFIG}")" = "stale" ]
}

@test "system install repairs an unreadable, empty system git config" {
    write_system_config '' 0640

    run_system_install

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
    system_config_has_hooks_path
}

@test "system install skips the repair before the dependency step when the system git config is missing" {
    local _sudo_log="${BATS_TEST_TMPDIR}/sudo.log"

    run_system_install FAKE_SUDO_LOG="${_sudo_log}"

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    grep -Fxq "test -e ${FAKE_SYSTEM_GITCONFIG}" "${_sudo_log}"
    # Only the chmod after writing the config, none for the missing file.
    [ "$(grep -c '^chmod ' "${_sudo_log}")" -eq 1 ]
    [ "$(system_config_mode)" = "644" ]
}

@test "system install falls back to the distro location when git cannot report the system git config path" {
    write_system_config 'stale' 0640

    run_system_install FAKE_GIT_FAIL_VAR=1 \
        SYSTEM_GIT_CONFIG_FALLBACK_TEST_OVERRIDE="${FAKE_SYSTEM_GITCONFIG}"

    [ "${status}" -eq 0 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
    system_config_has_hooks_path
}

@test "system install's fallback location is /etc/gitconfig" {
    # The fake sudo refuses every chmod, so /etc/gitconfig is never changed;
    # the install dies at whichever repair reaches it first.
    run_system_install FAKE_GIT_FAIL_VAR=1 FAKE_SUDO_FAIL_COMMAND=chmod

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (/etc/gitconfig) world-readable"* ]]
}

@test "system install dies before the dependency step when sudo fails to locate an unreadable system git config" {
    write_system_config 'stale' 0640

    run_system_install FAKE_SUDO_FAIL_COMMAND=true

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to run sudo to locate the system git config"* ]]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "640" ]
}

@test "system install dies when writing the system git config fails" {
    run_system_install FAKE_GIT_FAIL_WRITE=1

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to set core.hooksPath in the system git config"* ]]
}

@test "system install dies when sudo fails to locate the system git config after writing it" {
    write_system_config 'stale' 0644

    run_system_install FAKE_SUDO_FAIL_COMMAND=true

    [ "${status}" -eq 1 ]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
    system_config_has_hooks_path
    [[ "${output}" == *"Failed to run sudo to locate the system git config"* ]]
}

@test "system install dies when making the system git config world-readable fails" {
    run_system_install FAKE_SUDO_FAIL_COMMAND=chmod

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Failed to make the system git config (${FAKE_SYSTEM_GITCONFIG}) world-readable"* ]]
}

@test "system install skips the dependency step on an unrecognised distro" {
    printf 'ID=fedora\n' > "${FAKE_OS_RELEASE}"

    run_system_install

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Platform not recognised"* ]]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
}
