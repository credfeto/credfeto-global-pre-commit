#!/usr/bin/env bats
# Acceptance tests for check-setup's cscleanup detection: cscleanup counts as
# installed when it is a local dotnet tool in the $HOME manifest or, failing
# that, a global dotnet tool; when it is neither, the local-install hint shows.
# Also covers the pipx tools under --system: a copy that only resolves under
# $HOME, or a shared venv other users cannot read, is reported as failing.
#
# Runs check-setup with a PATH holding only a fake dotnet and the few
# utilities check-setup itself needs, and a per-test HOME, so the host's own
# dotnet, tool manifest and linters are never consulted or started. Every
# other linter is therefore missing, so only the cscleanup line is checked.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${FAKE_BIN}" "${FAKE_HOME}"

    # `tool list` reports cscleanup only when run from HOME with
    # FAKE_LOCAL_CSCLEANUP set; `tool list --global` only with
    # FAKE_GLOBAL_CSCLEANUP set. Every other call fails, so pwsh is absent.
    cat > "${FAKE_BIN}/dotnet" <<'FAKE'
#!/bin/sh
case "$*" in
    --version) printf '10.0.100\n' ;;
    "tool list")
        printf 'Package Id      Version      Commands      Manifest\n'
        if [ -n "${FAKE_LOCAL_CSCLEANUP:-}" ] && [ "$PWD" = "$HOME" ]; then
            printf 'credfeto.dotnet.repo.formatter 1.2.3 cscleanup %s/dotnet-tools.json\n' "$HOME"
        fi
        ;;
    "tool list --global"|"tool list -g")
        printf 'Package Id      Version      Commands\n'
        [ -z "${FAKE_GLOBAL_CSCLEANUP:-}" ] \
            || printf 'credfeto.dotnet.repo.formatter 9.9.9 cscleanup\n'
        ;;
    *) exit 1 ;;
esac
exit 0
FAKE
    chmod +x "${FAKE_BIN}/dotnet"

    local _util
    for _util in awk dirname find grep head readlink; do
        link_host_tool "${_util}" "${FAKE_BIN}" || return 1
    done
}

# run_check_setup [NAME=value ...]
run_check_setup() {
    run env HOME="${FAKE_HOME}" PATH="${FAKE_BIN}" "$@" "${REPO_DIR}/check-setup"
}

# run_check_setup_system [NAME=value ...]
run_check_setup_system() {
    run env HOME="${FAKE_HOME}" PATH="${FAKE_BIN}" "$@" "${REPO_DIR}/check-setup" --system
}

# write_tool <dir> <command>
# Writes a do-nothing executable <dir>/<command>, readable by every user.
write_tool() {
    mkdir -p "$1"
    printf '#!/bin/sh\nexit 0\n' > "$1/$2"
    chmod 0755 "$1/$2"
}

# write_shared_pipx_tool <package> <command>
# Lays out a pipx venv for <package> under a stand-in for the shared pipx home
# (outside HOME) and links <command> into a stand-in shared bin directory,
# returning the paths in SHARED_PIPX_HOME and SHARED_BIN.
write_shared_pipx_tool() {
    SHARED_PIPX_HOME="${BATS_TEST_TMPDIR}/opt/pipx"
    SHARED_BIN="${BATS_TEST_TMPDIR}/usr/local/bin"
    write_tool "${SHARED_PIPX_HOME}/venvs/$1/bin" "$2"
    printf 'home = /usr/bin\n' > "${SHARED_PIPX_HOME}/venvs/$1/pyvenv.cfg"
    chmod -R a+rX "${SHARED_PIPX_HOME}"
    mkdir -p "${SHARED_BIN}"
    ln -s "${SHARED_PIPX_HOME}/venvs/$1/bin/$2" "${SHARED_BIN}/$2"
}

pre_commit_hooks_line() {
    printf '%s\n' "${output}" | grep 'VALIDATE_JSON/XML/YAML/TOML syntax'
}

cscleanup_line() {
    printf '%s\n' "${output}" | grep 'cscleanup (\*.cs)'
}

@test "check-setup reports cscleanup installed as a local tool in the HOME manifest" {
    run_check_setup FAKE_LOCAL_CSCLEANUP=1
    local _line
    _line="$(cscleanup_line)"

    [[ "${_line}" == *"v1.2.3"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup reports cscleanup installed when it is only a global tool" {
    run_check_setup FAKE_GLOBAL_CSCLEANUP=1
    local _line
    _line="$(cscleanup_line)"

    [[ "${_line}" == *"v9.9.9"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup gives the local-install hint when cscleanup is neither a local nor a global tool" {
    run_check_setup
    local _line
    _line="$(cscleanup_line)"

    [[ "${_line}" == *"not installed"*"dotnet tool install Credfeto.DotNet.Repo.Formatter"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"--global"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails a pre-commit-hooks copy that is only under HOME, giving the shared install command" {
    write_tool "${FAKE_HOME}/.local/bin" check-merge-conflict

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"
    local _line
    _line="$(pre_commit_hooks_line)"

    [[ "${_line}" == *"installed only under ${FAKE_HOME}, so other users cannot run it"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" == *"sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install pre-commit-hooks"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" == *"pre-commit-hooks: (umask 022 && sudo env PIPX_HOME=/opt/pipx "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup accepts a pre-commit-hooks copy under HOME for a per-user install" {
    write_tool "${FAKE_HOME}/.local/bin" check-merge-conflict

    run_check_setup PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"
    local _line
    _line="$(pre_commit_hooks_line)"

    [[ "${_line}" == *"pre-commit-hooks (pipx)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"pre-commit-hooks: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a sqlfluff copy that is only under HOME" {
    write_tool "${FAKE_HOME}/.local/bin" sqlfluff

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"
    local _line
    _line="$(printf '%s\n' "${output}" | grep 'SQL style')"

    [[ "${_line}" == *"installed only under ${FAKE_HOME}, so other users cannot run it"*"pipx install sqlfluff"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system accepts a readable shared pre-commit-hooks copy even when a per-user copy comes first on PATH" {
    write_tool "${FAKE_HOME}/.local/bin" check-merge-conflict
    write_shared_pipx_tool pre-commit-hooks check-merge-conflict

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${SHARED_BIN}:${FAKE_BIN}" \
        PIPX_SHARED_HOME_TEST_OVERRIDE="${SHARED_PIPX_HOME}"
    local _line
    _line="$(pre_commit_hooks_line)"

    [[ "${_line}" == *"pre-commit-hooks (pipx)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"pre-commit-hooks: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a shared pre-commit-hooks venv that other users cannot read" {
    write_shared_pipx_tool pre-commit-hooks check-merge-conflict
    chmod 0640 "${SHARED_PIPX_HOME}/venvs/pre-commit-hooks/pyvenv.cfg"

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        PIPX_SHARED_HOME_TEST_OVERRIDE="${SHARED_PIPX_HOME}"
    local _line
    _line="$(pre_commit_hooks_line)"

    [[ "${_line}" == *"${SHARED_PIPX_HOME}/venvs/pre-commit-hooks is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" == *"sudo chmod -R a+rX ${SHARED_PIPX_HOME}"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails a shared pipx home whose venvs directory other users cannot enter" {
    write_shared_pipx_tool pre-commit-hooks check-merge-conflict
    chmod 0750 "${SHARED_PIPX_HOME}/venvs"

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        PIPX_SHARED_HOME_TEST_OVERRIDE="${SHARED_PIPX_HOME}"
    chmod 0755 "${SHARED_PIPX_HOME}/venvs"
    local _line
    _line="$(pre_commit_hooks_line)"

    [[ "${_line}" == *"is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup gives the shared pipx install command for a missing pre-commit-hooks" {
    run_check_setup

    [[ "${output}" == *"pre-commit-hooks: (umask 022 && sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install pre-commit-hooks) && sudo chmod -R a+rX /opt/pipx"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"pip install pre-commit-hooks"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a shared pre-commit-hooks command that other users cannot execute" {
    write_shared_pipx_tool pre-commit-hooks check-merge-conflict
    chmod 0744 "${SHARED_PIPX_HOME}/venvs/pre-commit-hooks/bin/check-merge-conflict"

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        PIPX_SHARED_HOME_TEST_OVERRIDE="${SHARED_PIPX_HOME}"
    local _line
    _line="$(pre_commit_hooks_line)"

    [[ "${_line}" == *"is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup accepts every pipx tool and gives no install hint for them when they are on PATH" {
    local _tool
    for _tool in check-merge-conflict sqlfluff cfn-lint pylint ansible-lint; do
        write_tool "${FAKE_HOME}/.local/bin" "${_tool}"
    done

    run_check_setup PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"

    for _tool in pre-commit-hooks sqlfluff cfn-lint pylint ansible-lint; do
        [[ "${output}" != *"  ${_tool}: "* ]] \
            || fail_with_run_output "${status}" "${output}" "any"
    done
    [[ "$(printf '%s\n' "${output}" | grep -E 'sqlfluff \(\*\.sql\)|CloudFormation|VALIDATE_ANSIBLE|VALIDATE_PYTHON_PYLINT')" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system accepts a shared pipx tool installed outside the shared pipx venvs" {
    SHARED_BIN="${BATS_TEST_TMPDIR}/usr/bin"
    write_tool "${SHARED_BIN}" pylint

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        PIPX_SHARED_HOME_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/opt/pipx"
    local _line
    _line="$(printf '%s\n' "${output}" | grep 'VALIDATE_PYTHON_PYLINT')"

    [[ "${_line}" != *"not installed"* && "${_line}" != *"other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"  pylint: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}
