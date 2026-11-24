#!/usr/bin/env bats
# Acceptance tests for check-setup's cscleanup detection: cscleanup counts as
# installed when it is a local dotnet tool in the $HOME manifest or, failing
# that, a global or shared dotnet tool; when it is none of them, the
# local-install hint shows. Under --system only a shared copy every user can
# read counts. Also covers the pipx and npm tools and actionlint under
# --system: a copy that only resolves under $HOME, a shared venv, npm package
# or binary other users cannot read, or an npm tool whose node other users
# cannot run, is reported as failing.
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
    # Where an nvm-managed Node.js and its global npm packages live under HOME.
    NVM_BIN="${FAKE_HOME}/.nvm/versions/node/v22.0.0/bin"
    mkdir -p "${FAKE_BIN}" "${FAKE_HOME}"

    # `tool list` reports cscleanup only when run from HOME with
    # FAKE_LOCAL_CSCLEANUP set; `tool list --global` only with
    # FAKE_GLOBAL_CSCLEANUP set; `tool list --tool-path <shared tool path>`
    # only with FAKE_SHARED_CSCLEANUP set. Every other dotnet call fails.
    SHARED_TOOLS="${BATS_TEST_TMPDIR}/opt/dotnet-tools"
    SHARED_BIN_DIR="${BATS_TEST_TMPDIR}/usr/local/bin"
    export DOTNET_SHARED_TOOLS_TEST_OVERRIDE="${SHARED_TOOLS}"
    export SHARED_BIN_DIR_TEST_OVERRIDE="${SHARED_BIN_DIR}"
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
    "tool list --tool-path $DOTNET_SHARED_TOOLS_TEST_OVERRIDE")
        printf 'Package Id      Version      Commands\n'
        [ -z "${FAKE_SHARED_CSCLEANUP:-}" ] \
            || printf 'credfeto.dotnet.repo.formatter 3.4.5 cscleanup\n'
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

# output_line <pattern>
# Prints the line(s) of the last run's output matching the grep <pattern>.
output_line() {
    printf '%s\n' "${output}" | grep -- "$1"
}

@test "check-setup reports cscleanup installed as a local tool in the HOME manifest" {
    run_check_setup FAKE_LOCAL_CSCLEANUP=1
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"v1.2.3"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup reports cscleanup installed when it is only a global tool" {
    run_check_setup FAKE_GLOBAL_CSCLEANUP=1
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"v9.9.9"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup gives the local-install hint when cscleanup is neither a local nor a global tool" {
    run_check_setup
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"not installed"*"dotnet tool install Credfeto.DotNet.Repo.Formatter"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"--global"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

# write_shared_cscleanup
# Lays out a stand-in for the shared dotnet tool path, readable by every user.
write_shared_cscleanup() {
    write_tool "${SHARED_TOOLS}" cscleanup
    chmod -R a+rX "${SHARED_TOOLS}"
}

@test "check-setup reports cscleanup installed when it is only a shared tool" {
    write_shared_cscleanup

    run_check_setup FAKE_SHARED_CSCLEANUP=1
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"v3.4.5"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a cscleanup that is only in the HOME manifest, giving the shared install command" {
    run_check_setup_system FAKE_LOCAL_CSCLEANUP=1 FAKE_GLOBAL_CSCLEANUP=1
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"not installed for every user; run: ./install-deps-arch or ./install-deps-debian (installs cscleanup for every user)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system accepts a shared cscleanup every user can read" {
    write_shared_cscleanup

    run_check_setup_system FAKE_SHARED_CSCLEANUP=1
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"v3.4.5"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"other users"* && "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a shared cscleanup that other users cannot run" {
    write_shared_cscleanup
    chmod 0744 "${SHARED_TOOLS}/cscleanup"

    run_check_setup_system FAKE_SHARED_CSCLEANUP=1
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"${SHARED_TOOLS} is not readable and executable by other users, so they cannot run it"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails a shared cscleanup whose parent directory other users cannot enter" {
    write_shared_cscleanup
    chmod 0750 "${SHARED_TOOLS%/*}"

    run_check_setup_system FAKE_SHARED_CSCLEANUP=1
    chmod 0755 "${SHARED_TOOLS%/*}"
    local _line
    _line="$(output_line 'cscleanup (\*.cs)')"

    [[ "${_line}" == *"is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails an actionlint that is only under HOME, giving the shared install command" {
    write_tool "${FAKE_HOME}/go/bin" actionlint "echo 1.7.12"

    run_check_setup_system PATH="${FAKE_HOME}/go/bin:${FAKE_BIN}"
    local _line
    _line="$(output_line 'VALIDATE_GITHUB_ACTIONS workflows')"

    [[ "${_line}" == *"installed only under ${FAKE_HOME}, so other users cannot run it; run: ./install-deps-arch or ./install-deps-debian (installs actionlint for every user)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" == *"  actionlint:             ./install-deps-arch or ./install-deps-debian (installs actionlint for every user)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"go install"*"actionlint"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup accepts an actionlint under HOME for a per-user install" {
    write_tool "${FAKE_HOME}/go/bin" actionlint "echo 1.7.12"

    run_check_setup PATH="${FAKE_HOME}/go/bin:${FAKE_BIN}"
    local _line
    _line="$(output_line 'VALIDATE_GITHUB_ACTIONS workflows')"

    [[ "${_line}" == *"1.7.12"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"  actionlint: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system accepts a shared actionlint every user can run" {
    write_tool "${SHARED_BIN_DIR}" actionlint "echo 1.7.12"

    run_check_setup_system PATH="${SHARED_BIN_DIR}:${FAKE_BIN}"
    local _line
    _line="$(output_line 'VALIDATE_GITHUB_ACTIONS workflows')"

    [[ "${_line}" == *"1.7.12"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"  actionlint: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a shared actionlint that other users cannot run" {
    write_tool "${SHARED_BIN_DIR}" actionlint "echo 1.7.12"
    chmod 0744 "${SHARED_BIN_DIR}/actionlint"

    run_check_setup_system PATH="${SHARED_BIN_DIR}:${FAKE_BIN}"
    local _line
    _line="$(output_line 'VALIDATE_GITHUB_ACTIONS workflows')"

    [[ "${_line}" == *"${SHARED_BIN_DIR}/actionlint is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails a pre-commit that is only under HOME" {
    write_tool "${FAKE_HOME}/.local/bin" pre-commit

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"
    local _line
    _line="$(output_line 'pre-commit linters')"

    [[ "${_line}" == *"pre-commit installed only under ${FAKE_HOME}, so other users cannot run it"*"pipx install pre-commit"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup gives the shared pipx install commands for a missing pre-commit, yamllint and flake8" {
    run_check_setup

    local _tool
    for _tool in pre-commit yamllint flake8; do
        [[ "${output}" == *"  ${_tool}: "*"(umask 022 && sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install ${_tool}) && sudo chmod -R a+rX /opt/pipx"* ]] \
            || fail_with_run_output "${status}" "${output}" "any"
        [[ "${output}" != *"pip install ${_tool}"* ]] \
            || fail_with_run_output "${status}" "${output}" "any"
    done
}

@test "check-setup --system fails a pre-commit-hooks copy that is only under HOME, giving the shared install command" {
    write_tool "${FAKE_HOME}/.local/bin" check-merge-conflict

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"
    local _line
    _line="$(output_line 'VALIDATE_JSON/XML/YAML/TOML syntax')"

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
    _line="$(output_line 'VALIDATE_JSON/XML/YAML/TOML syntax')"

    [[ "${_line}" == *"pre-commit-hooks (pipx)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"pre-commit-hooks: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a sqlfluff copy that is only under HOME" {
    write_tool "${FAKE_HOME}/.local/bin" sqlfluff

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${FAKE_BIN}"
    local _line
    _line="$(output_line 'SQL style')"

    [[ "${_line}" == *"installed only under ${FAKE_HOME}, so other users cannot run it"*"pipx install sqlfluff"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system accepts a readable shared pre-commit-hooks copy even when a per-user copy comes first on PATH" {
    write_tool "${FAKE_HOME}/.local/bin" check-merge-conflict
    write_shared_pipx_tool pre-commit-hooks check-merge-conflict

    run_check_setup_system PATH="${FAKE_HOME}/.local/bin:${SHARED_BIN}:${FAKE_BIN}" \
        PIPX_SHARED_HOME_TEST_OVERRIDE="${SHARED_PIPX_HOME}"
    local _line
    _line="$(output_line 'VALIDATE_JSON/XML/YAML/TOML syntax')"

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
    _line="$(output_line 'VALIDATE_JSON/XML/YAML/TOML syntax')"

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
    _line="$(output_line 'VALIDATE_JSON/XML/YAML/TOML syntax')"

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
    _line="$(output_line 'VALIDATE_JSON/XML/YAML/TOML syntax')"

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
    _line="$(output_line 'VALIDATE_PYTHON_PYLINT')"

    [[ "${_line}" != *"not installed"* && "${_line}" != *"other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"  pylint: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

# write_shared_npm_tool <package> <command>
# Lays out <package> under a stand-in for the shared npm prefix's
# lib/node_modules (outside HOME), links <command> to it from the prefix's bin
# directory, and puts a readable node there too, returning the prefix in
# SHARED_NPM_PREFIX and its bin directory in SHARED_BIN.
write_shared_npm_tool() {
    SHARED_NPM_PREFIX="${BATS_TEST_TMPDIR}/usr/local"
    SHARED_BIN="${SHARED_NPM_PREFIX}/bin"
    write_tool "${SHARED_NPM_PREFIX}/lib/node_modules/$1/bin" "$2.js"
    printf '{"name": "%s"}\n' "$1" > "${SHARED_NPM_PREFIX}/lib/node_modules/$1/package.json"
    chmod -R a+rX "${SHARED_NPM_PREFIX}"
    mkdir -p "${SHARED_BIN}"
    ln -s "../lib/node_modules/$1/bin/$2.js" "${SHARED_BIN}/$2"
    write_tool "${SHARED_BIN}" node
}

@test "check-setup --system fails an npm linter that is only under HOME, giving the shared npm install command" {
    write_tool "${NVM_BIN}" eslint
    write_tool "${NVM_BIN}" node

    run_check_setup_system PATH="${NVM_BIN}:${FAKE_BIN}"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" == *"installed only under ${FAKE_HOME}, so other users cannot run it"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" == *"(umask 022 && sudo npm install --global --prefix /usr/local --engine-strict --ignore-scripts eslint) && sudo chmod -R a+rX /usr/local/lib/node_modules"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" == *"  eslint:         (umask 022 && sudo npm install --global --prefix /usr/local --engine-strict --ignore-scripts eslint)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails markdownlint and stylelint copies that are only under HOME" {
    write_tool "${NVM_BIN}" markdownlint
    write_tool "${NVM_BIN}" stylelint

    run_check_setup_system PATH="${NVM_BIN}:${FAKE_BIN}"

    [[ "$(output_line 'VALIDATE_MD')" == *"installed only under ${FAKE_HOME}"*"--ignore-scripts markdownlint-cli)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "$(output_line 'VALIDATE_CSS')" == *"installed only under ${FAKE_HOME}"*"--ignore-scripts stylelint)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" == *"  stylelint:      (umask 022 && sudo npm install --global --prefix /usr/local --engine-strict --ignore-scripts stylelint stylelint-config-standard)"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup accepts every npm linter under HOME for a per-user install, giving no install hint for them" {
    local _tool
    for _tool in markdownlint stylelint eslint; do
        write_tool "${NVM_BIN}" "${_tool}"
    done

    run_check_setup PATH="${NVM_BIN}:${FAKE_BIN}"

    for _tool in markdownlint stylelint eslint; do
        [[ "${output}" != *"  ${_tool}: "* ]] \
            || fail_with_run_output "${status}" "${output}" "any"
    done
    [[ "$(printf '%s\n' "${output}" | grep -E 'VALIDATE_MD|VALIDATE_CSS|VALIDATE_TYPESCRIPT_ES')" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system accepts a readable shared npm linter even when a per-user copy comes first on PATH" {
    write_tool "${NVM_BIN}" eslint
    write_tool "${NVM_BIN}" node
    write_shared_npm_tool eslint eslint

    run_check_setup_system PATH="${NVM_BIN}:${SHARED_BIN}:${FAKE_BIN}" \
        NPM_SHARED_PREFIX_TEST_OVERRIDE="${SHARED_NPM_PREFIX}"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" != *"not installed"* && "${_line}" != *"other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"  eslint: "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a shared npm package that other users cannot read" {
    write_shared_npm_tool eslint eslint
    chmod 0640 "${SHARED_NPM_PREFIX}/lib/node_modules/eslint/package.json"

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        NPM_SHARED_PREFIX_TEST_OVERRIDE="${SHARED_NPM_PREFIX}"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" == *"${SHARED_NPM_PREFIX}/lib/node_modules/eslint is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" == *"sudo chmod -R a+rX ${SHARED_NPM_PREFIX}/lib/node_modules"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails a shared npm prefix whose node_modules directory other users cannot enter" {
    write_shared_npm_tool eslint eslint
    chmod 0750 "${SHARED_NPM_PREFIX}/lib/node_modules"

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        NPM_SHARED_PREFIX_TEST_OVERRIDE="${SHARED_NPM_PREFIX}"
    chmod 0755 "${SHARED_NPM_PREFIX}/lib/node_modules"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" == *"is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system fails a shared npm linter whose node is only under HOME" {
    write_shared_npm_tool eslint eslint
    rm "${SHARED_BIN}/node"
    write_tool "${NVM_BIN}" node

    run_check_setup_system PATH="${SHARED_BIN}:${NVM_BIN}:${FAKE_BIN}" \
        NPM_SHARED_PREFIX_TEST_OVERRIDE="${SHARED_NPM_PREFIX}"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" == *"needs node, which is not installed outside ${FAKE_HOME}, so other users cannot run it; run: ./install-deps-arch or ./install-deps-debian"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}

@test "check-setup --system fails a shared npm linter whose shared node other users cannot execute" {
    write_shared_npm_tool eslint eslint
    chmod 0744 "${SHARED_BIN}/node"

    run_check_setup_system PATH="${SHARED_BIN}:${FAKE_BIN}" \
        NPM_SHARED_PREFIX_TEST_OVERRIDE="${SHARED_NPM_PREFIX}"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" == *"needs node, but ${SHARED_BIN}/node is not readable and executable by other users"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup --system accepts a shared npm linter installed outside the shared npm prefix" {
    local _usr_bin="${BATS_TEST_TMPDIR}/usr/bin"
    write_tool "${_usr_bin}" eslint
    write_tool "${_usr_bin}" node

    run_check_setup_system PATH="${_usr_bin}:${FAKE_BIN}" \
        NPM_SHARED_PREFIX_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/usr/local"
    local _line
    _line="$(output_line 'VALIDATE_TYPESCRIPT_ES')"

    [[ "${_line}" != *"not installed"* && "${_line}" != *"other users"* && "${_line}" != *"needs node"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup gives the shared npm install commands for missing npm linters" {
    run_check_setup

    [[ "${output}" == *"  markdownlint:   (umask 022 && sudo npm install --global --prefix /usr/local --engine-strict --ignore-scripts markdownlint-cli) && sudo chmod -R a+rX /usr/local/lib/node_modules"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${output}" != *"npm install -g "* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}
