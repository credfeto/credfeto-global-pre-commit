#!/usr/bin/env bats
# Acceptance tests for check-setup's cscleanup detection: cscleanup counts as
# installed when it is a local dotnet tool in the $HOME manifest or, failing
# that, a global dotnet tool; when it is neither, the local-install hint shows.
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
    for _util in awk dirname grep head; do
        ln -s "$(command -v "${_util}")" "${FAKE_BIN}/${_util}"
    done
}

# run_check_setup [NAME=value ...]
run_check_setup() {
    run env HOME="${FAKE_HOME}" PATH="${FAKE_BIN}" "$@" "${REPO_DIR}/check-setup"
}

cscleanup_line() {
    printf '%s\n' "${output}" | grep 'cscleanup (\*.cs)'
}

@test "check-setup reports cscleanup installed as a local tool in the HOME manifest" {
    run_check_setup FAKE_LOCAL_CSCLEANUP=1
    _line="$(cscleanup_line)"

    [[ "${_line}" == *"v1.2.3"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup reports cscleanup installed when it is only a global tool" {
    run_check_setup FAKE_GLOBAL_CSCLEANUP=1
    _line="$(cscleanup_line)"

    [[ "${_line}" == *"v9.9.9"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"not installed"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
}

@test "check-setup gives the local-install hint when cscleanup is neither a local nor a global tool" {
    run_check_setup
    _line="$(cscleanup_line)"

    [[ "${_line}" == *"not installed"*"dotnet tool install Credfeto.DotNet.Repo.Formatter"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [[ "${_line}" != *"--global"* ]] \
        || fail_with_run_output "${status}" "${output}" "any"
    [ "${status}" -ne 0 ]
}
