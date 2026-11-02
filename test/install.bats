#!/usr/bin/env bats
# Acceptance tests for the --system path of install: the system git config it
# writes through sudo must end up readable by every user even when the caller's
# umask is restrictive, because sudo keeps that umask, and one an earlier
# install left unreadable must be repaired before the dependency step, which
# runs git as the user. Only read bits are added, so other mode bits an admin
# chose are kept. Also covers making the listed files executable (with a sudo
# retry for --system) and linking or copying the wrappers and
# composite-action-lint for each install mode, and guards that
# install-deps-arch never calls an AUR helper or makepkg, since everything it
# installs comes from pacman repos or releases.
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
    # The real dependency step can run git as the user (the nvm installer on
    # Debian), so the stub does too and records that git worked.
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

    # Logs each call, marked root when run through the fake sudo, and with
    # FAKE_CHMOD_FAIL set refuses every non-root call as chmod does on a file
    # the caller does not own; otherwise hands over to the real chmod.
    export FAKE_REAL_CHMOD
    FAKE_REAL_CHMOD="$(command -v chmod)"
    cat > "${FAKE_BIN}/chmod" <<'EOF'
#!/bin/sh
_caller=user
[ -z "${FAKE_SUDO_AS_ROOT:-}" ] || _caller=root
[ -z "${FAKE_CHMOD_LOG:-}" ] || printf '%s %s\n' "$_caller" "$*" >> "$FAKE_CHMOD_LOG"
if [ -n "${FAKE_CHMOD_FAIL:-}" ] && [ -z "${FAKE_SUDO_AS_ROOT:-}" ]; then
    printf "chmod: changing permissions of '%s': Operation not permitted\n" "$2" >&2
    exit 1
fi
exec "$FAKE_REAL_CHMOD" "$@"
EOF
    chmod +x "${FAKE_BIN}/chmod"

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
    "config --global --get core.hooksPath" | "config --system --get core.hooksPath")
        exit 1
        ;;
    "config --global core.hooksPath "*)
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

    # Stands in for the host's go, which is often on TEST_PATH, so no test
    # depends on the host's Go bin directory. Its GOPATH has no tools until a
    # test adds one.
    export FAKE_GOPATH="${BATS_TEST_TMPDIR}/gopath"
    mkdir -p "${FAKE_GOPATH}/bin"
    cat > "${FAKE_BIN}/go" <<'EOF'
#!/bin/sh
[ "$*" = "env GOPATH" ] || exit 2
printf '%s\n' "$FAKE_GOPATH"
EOF
    chmod +x "${FAKE_BIN}/go"

    # Every install sees this, so a --system install never writes into the
    # real /usr/local/bin.
    export SYSTEM_BIN_DIR_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/system-bin"
    mkdir -p "${SYSTEM_BIN_DIR_TEST_OVERRIDE}"

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
    run_installer --system "$@"
}

# run_user_install [NAME=value ...]
# As run_system_install, without --system.
run_user_install() {
    run_installer "" "$@"
}

# run_installer FLAG [NAME=value ...]
# Runs the staged install in the fake environment, passing FLAG when it is
# not empty.
run_installer() {
    local _flag="$1"
    shift
    run env HOME="${BATS_TEST_TMPDIR}/home" PATH="${FAKE_BIN}:${TEST_PATH}" \
        OS_RELEASE_TEST_OVERRIDE="${FAKE_OS_RELEASE}" "$@" "${STAGE}/install" ${_flag:+"${_flag}"}
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

@test "system install runs no chmod +x when every listed file is already executable" {
    local _chmod_log="${BATS_TEST_TMPDIR}/chmod.log"

    run_system_install FAKE_CHMOD_LOG="${_chmod_log}" FAKE_CHMOD_FAIL=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(grep -c -- ' +x ' "${_chmod_log}")" -eq 0 ]
    system_config_has_hooks_path
}

@test "system install retries a refused chmod +x with sudo and goes on to set core.hooksPath" {
    local _chmod_log="${BATS_TEST_TMPDIR}/chmod.log"
    local _sudo_log="${BATS_TEST_TMPDIR}/sudo.log"
    local _script="${STAGE}/src/scripts/run-bats"
    chmod -x "${_script}"

    run_system_install FAKE_CHMOD_LOG="${_chmod_log}" FAKE_SUDO_LOG="${_sudo_log}" FAKE_CHMOD_FAIL=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    grep -Fxq "user +x ${_script}" "${_chmod_log}"
    grep -Fxq "root +x ${_script}" "${_chmod_log}"
    grep -Fxq "chmod +x ${_script}" "${_sudo_log}"
    # Only the file that was not executable is changed.
    [ "$(grep -c -- ' +x ' "${_chmod_log}")" -eq 2 ]
    [ -x "${_script}" ]
    system_config_has_hooks_path
}

@test "system install dies naming the file when the sudo chmod +x retry fails" {
    local _script="${STAGE}/src/scripts/run-bats"
    chmod -x "${_script}"

    run_system_install FAKE_CHMOD_FAIL=1 FAKE_SUDO_FAIL_COMMAND=chmod

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"Failed to make ${_script} executable, even with sudo"* ]]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ ! -e "${FAKE_SYSTEM_GITCONFIG}" ]
}

@test "per-user install dies naming the file when chmod +x fails" {
    local _sudo_log="${BATS_TEST_TMPDIR}/sudo.log"
    local _script="${STAGE}/src/scripts/run-bats"
    chmod -x "${_script}"

    run_user_install FAKE_CHMOD_FAIL=1 FAKE_SUDO_LOG="${_sudo_log}"

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"Operation not permitted"* ]]
    [[ "${output}" == *"Failed to make ${_script} executable"* ]]
    [[ "${output}" != *"even with sudo"* ]]
    [ ! -e "${_sudo_log}" ]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
}

WRAPPER_LINKS="run-eslint run-stylelint run-psscriptanalyzer run-bats run-pylint"

# Prints a PATH holding the fakes and only the host tools the installer and
# its stubs need, so go is missing even when the host keeps it in /usr/bin.
path_without_go() {
    local _dir="${BATS_TEST_TMPDIR}/no-go-bin"
    local _tool
    mkdir -p "${_dir}"
    for _tool in "${FAKE_BIN}"/*; do
        [ "$(basename "${_tool}")" = go ] || ln -s "${_tool}" "${_dir}/"
    done
    for _tool in cat cut dirname grep install ln mkdir stat tr true; do
        ln -s "$(type -P "${_tool}")" "${_dir}/${_tool}"
    done
    printf '%s' "${_dir}"
}

add_fake_composite_action_lint() {
    printf '#!/bin/sh\nexit 0\n' > "${FAKE_GOPATH}/bin/composite-action-lint"
    chmod 0700 "${FAKE_GOPATH}/bin/composite-action-lint"
}

@test "system install links no wrappers into the user's bin directory" {
    run_system_install

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    for _link in ${WRAPPER_LINKS}; do
        [ ! -e "${BATS_TEST_TMPDIR}/home/.local/bin/${_link}" ]
        [ ! -L "${BATS_TEST_TMPDIR}/home/.local/bin/${_link}" ]
    done
}

@test "per-user install links the wrappers into the user's bin directory" {
    run_user_install

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    for _link in ${WRAPPER_LINKS}; do
        [ "$(readlink "${BATS_TEST_TMPDIR}/home/.local/bin/${_link}")" = "${STAGE}/src/scripts/${_link}" ]
    done
}

@test "per-user install links composite-action-lint into the user's bin directory" {
    add_fake_composite_action_lint

    run_user_install

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(readlink "${BATS_TEST_TMPDIR}/home/.local/bin/composite-action-lint")" = "${FAKE_GOPATH}/bin/composite-action-lint" ]
}

@test "system install copies composite-action-lint into the system bin directory with mode 0755" {
    local _sudo_log="${BATS_TEST_TMPDIR}/sudo.log"
    local _target="${SYSTEM_BIN_DIR_TEST_OVERRIDE}/composite-action-lint"
    add_fake_composite_action_lint

    run_system_install FAKE_SUDO_LOG="${_sudo_log}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    grep -Fxq "install -m 0755 ${FAKE_GOPATH}/bin/composite-action-lint ${_target}" "${_sudo_log}"
    [ ! -L "${_target}" ]
    [ "$(stat -c %a "${_target}")" = "755" ]
    [ ! -e "${BATS_TEST_TMPDIR}/home/.local/bin/composite-action-lint" ]
}

@test "system install installs nothing when go has no composite-action-lint" {
    local _sudo_log="${BATS_TEST_TMPDIR}/sudo.log"

    run_system_install FAKE_SUDO_LOG="${_sudo_log}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    run ! grep -q '^install ' "${_sudo_log}"
    [ -z "$(ls -A "${SYSTEM_BIN_DIR_TEST_OVERRIDE}")" ]
}

@test "system install installs nothing and succeeds when go is missing" {
    local _sudo_log="${BATS_TEST_TMPDIR}/sudo.log"
    add_fake_composite_action_lint

    run_system_install FAKE_SUDO_LOG="${_sudo_log}" PATH="$(path_without_go)"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    system_config_has_hooks_path
    run ! grep -q '^install ' "${_sudo_log}"
    [ -z "$(ls -A "${SYSTEM_BIN_DIR_TEST_OVERRIDE}")" ]
}

@test "system install warns naming composite-action-lint and carries on to check-setup when the sudo install fails" {
    local _check_setup_marker="${BATS_TEST_TMPDIR}/check-setup.ran"
    add_fake_composite_action_lint
    printf '#!/bin/sh\n: > "%s"\n' "${_check_setup_marker}" > "${STAGE}/check-setup"

    run_system_install FAKE_SUDO_FAIL_COMMAND=install

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"warning: Failed to install ${FAKE_GOPATH}/bin/composite-action-lint into ${SYSTEM_BIN_DIR_TEST_OVERRIDE}"* ]]
    [ ! -e "${SYSTEM_BIN_DIR_TEST_OVERRIDE}/composite-action-lint" ]
    system_config_has_hooks_path
    [ -e "${_check_setup_marker}" ]
}

@test "system install skips the dependency step on an unrecognised distro" {
    printf 'ID=fedora\n' > "${FAKE_OS_RELEASE}"

    run_system_install

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"→ Platform not recognised: skipping dependency install."* ]]
    [[ "${output}" == *"Run ./install-deps-arch or ./install-deps-debian manually."* ]]
    [ ! -e "${FAKE_DEPS_RAN_MARKER}" ]
    [ "$(system_config_mode)" = "644" ]
}

@test "system install runs install-deps-arch on an Arch-based distro" {
    # Only the Arch step may record that it ran.
    printf '#!/bin/sh\nexit 1\n' > "${STAGE}/install-deps-debian"

    run_system_install

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"→ Detected Arch-based Linux: running install-deps-arch..."* ]]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
}

@test "system install runs install-deps-debian on a Debian-based distro" {
    printf 'ID=ubuntu\nID_LIKE=debian\n' > "${FAKE_OS_RELEASE}"
    # Only the Debian step may record that it ran.
    printf '#!/bin/sh\nexit 1\n' > "${STAGE}/install-deps-arch"

    run_system_install

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"→ Detected Debian-based Linux: running install-deps-debian..."* ]]
    [ -e "${FAKE_DEPS_RAN_MARKER}" ]
}

# Comment lines are dropped first, so prose naming these tools is not a call.
non_comment_lines() {
    grep -v '^[[:space:]]*#' "$1"
}

@test "install-deps-arch never invokes an AUR helper or makepkg" {
    _code="$(non_comment_lines "${REPO_DIR}/install-deps-arch")"

    [ -n "${_code}" ]
    run grep -Ew 'paru|yay|makepkg' <<< "${_code}"
    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
}
