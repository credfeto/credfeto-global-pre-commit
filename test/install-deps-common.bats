#!/usr/bin/env bats
# Acceptance tests for the install helpers in lib/common.sh shared by
# install-deps-arch and install-deps-debian: install_release_linters,
# install_npm_globals, install_composite_action_lint, install_pwsh and
# install_cscleanup.
#
# Never installs anything: each helper runs in a bash whose PATH holds only
# fakes, so the host's own node, npm, go or dotnet can never be found,
# install_github_release is replaced by a function that records its arguments,
# and HOME is a per-test directory, so the host's own dotnet tool manifest is
# never seen.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    FAKE_GOPATH="${BATS_TEST_TMPDIR}/gopath"
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${FAKE_BIN}" "${FAKE_GOPATH}/bin" "${FAKE_HOME}"

    export CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
    export FAKE_GOPATH
    : > "${CALL_LOG}"

    cat > "${FAKE_BIN}/npm" <<'EOF'
#!/bin/sh
printf 'npm %s\n' "$*" >> "$CALL_LOG"
[ -z "${FAKE_NPM_FAIL:-}" ] || exit 1
EOF
    chmod +x "${FAKE_BIN}/npm"
    cat > "${FAKE_BIN}/go" <<'EOF'
#!/bin/sh
if [ "$*" = "env GOPATH" ]; then
    printf '%s\n' "$FAKE_GOPATH"
    exit 0
fi
printf 'go %s\n' "$*" >> "$CALL_LOG"
[ -z "${FAKE_GO_FAIL:-}" ] || exit 1
EOF
    chmod +x "${FAKE_BIN}/go"
}

# write_dotnet_fake
# Writes a fake dotnet. `dotnet tool list` prints the column headings and then
# FAKE_DOTNET_TOOLS (one "<package> <version> <command> <manifest>" row per
# line). Every other call is recorded with the directory it ran in, and fails
# when its arguments start with FAKE_DOTNET_FAIL (e.g. "tool install").
write_dotnet_fake() {
    cat > "${FAKE_BIN}/dotnet" <<'EOF'
#!/bin/sh
if [ "$*" = "tool list" ]; then
    printf 'Package Id      Version      Commands      Manifest\n'
    printf -- '----------------------------------------------------\n'
    [ -z "${FAKE_DOTNET_TOOLS:-}" ] || printf '%s\n' "$FAKE_DOTNET_TOOLS"
    exit 0
fi
printf 'dotnet %s (in %s)\n' "$*" "$PWD" >> "$CALL_LOG"
case "$*" in
    "${FAKE_DOTNET_FAIL:-no failure requested}"*) exit 1 ;;
esac
exit 0
EOF
    chmod +x "${FAKE_BIN}/dotnet"
    # The installed-tool check pipes `dotnet tool list` through awk, which the
    # fakes-only PATH would otherwise hide.
    ln -s "$(command -v awk)" "${FAKE_BIN}/awk"
}

# write_present_fake <command>
# Writes a fake that only exists, so the helper sees the command as installed.
write_present_fake() {
    printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/$1"
    chmod +x "${FAKE_BIN}/$1"
}

# run_helper [--separate-stderr] <helper> [extra PATH entry] [helper args...]
# Sources lib/common.sh into a bash whose PATH is the fakes (plus the extra
# entry, if not empty) and whose HOME is FAKE_HOME, stubs
# install_github_release, and runs <helper> with the helper args. The stub
# fails for the tool named in FAKE_RELEASE_FAIL.
# --separate-stderr is passed to bats' run, which then leaves stderr in
# ${stderr} instead of merging it into ${output}.
run_helper() {
    local -a _run_flags=()
    if [ "$1" = "--separate-stderr" ]; then
        _run_flags=("$1")
        shift
    fi
    local _path="${FAKE_BIN}${2:+:$2}"
    # shellcheck disable=SC2016 # expanded by the inner bash, not here
    run "${_run_flags[@]}" env PATH="${_path}" HOME="${FAKE_HOME}" "${BASH}" -c '
        . "$1"
        install_github_release() {
            printf "release %s\n" "$*" >> "$CALL_LOG"
            [ "$1" != "${FAKE_RELEASE_FAIL:-}" ]
        }
        "$2" "${@:3}"
    ' _ "${REPO_DIR}/lib/common.sh" "$1" "${@:3}"
}

calls() {
    cat "${CALL_LOG}"
}

@test "install_release_linters requests hadolint, dotenv-linter and trufflehog with their asset templates on x86_64" {
    ARCH_UNAME=x86_64 run_helper install_release_linters

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    _expected="release hadolint hadolint/hadolint hadolint-linux-x86_64 BIN
release dotenv-linter dotenv-linter/dotenv-linter dotenv-linter-linux-UARCH.tar.gz
release trufflehog trufflesecurity/trufflehog trufflehog_VERSION_linux_ARCH.tar.gz"
    [ "$(calls)" = "${_expected}" ]
}

@test "install_release_linters requests hadolint's arm64 asset on aarch64" {
    ARCH_UNAME=aarch64 run_helper install_release_linters

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    _expected="release hadolint hadolint/hadolint hadolint-linux-arm64 BIN
release dotenv-linter dotenv-linter/dotenv-linter dotenv-linter-linux-UARCH.tar.gz
release trufflehog trufflesecurity/trufflehog trufflehog_VERSION_linux_ARCH.tar.gz"
    [ "$(calls)" = "${_expected}" ]
}

@test "install_release_linters fails, and stops, when a release install fails" {
    ARCH_UNAME=x86_64 FAKE_RELEASE_FAIL=dotenv-linter run_helper install_release_linters

    [ "${status}" -ne 0 ] || fail_with_run_output "${status}" "${output}" "non-zero"
    [[ "$(calls)" == *"release dotenv-linter "* ]]
    [[ "$(calls)" != *"release trufflehog "* ]]
}

@test "install_npm_globals installs the global npm linters when node is on PATH" {
    write_present_fake node

    run_helper install_npm_globals

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(calls)" = "npm install --global markdownlint-cli eslint stylelint stylelint-config-standard" ]
}

@test "install_npm_globals skips npm when node is not on PATH" {
    run_helper install_npm_globals

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"node not active in nvm, skipping npm global packages"* ]]
    [ -z "$(calls)" ]
}

@test "install_npm_globals adds the nvm setup hint to the skip message when nvm is not loaded" {
    NVM_DIR='' run_helper install_npm_globals "" "source the nvm init script"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"node not active in nvm, skipping npm global packages; nvm is not loaded, so source the nvm init script"* ]]
    [ -z "$(calls)" ]
}

@test "install_npm_globals leaves out the nvm setup hint when nvm is loaded" {
    NVM_DIR="${FAKE_HOME}/.nvm" run_helper install_npm_globals "" "source the nvm init script"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"node not active in nvm, skipping npm global packages"* ]]
    [[ "${output}" != *"nvm is not loaded"* ]]
    [ -z "$(calls)" ]
}

@test "install_npm_globals fails when npm fails" {
    write_present_fake node

    FAKE_NPM_FAIL=1 run_helper install_npm_globals

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"npm global install failed"* ]]
}

@test "install_composite_action_lint go installs composite-action-lint when it is missing" {
    run_helper install_composite_action_lint "${FAKE_GOPATH}/bin"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(calls)" = "go install github.com/bettermarks/composite-action-lint/cmd/composite-action-lint@latest" ]
    [[ "${output}" != *"warning:"* ]]
}

@test "install_composite_action_lint skips go install when composite-action-lint is already installed" {
    write_present_fake composite-action-lint

    run_helper install_composite_action_lint "${FAKE_GOPATH}/bin"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"composite-action-lint already installed, skipping"* ]]
    [ -z "$(calls)" ]
}

@test "install_composite_action_lint fails when go install fails" {
    FAKE_GO_FAIL=1 run_helper install_composite_action_lint "${FAKE_GOPATH}/bin"

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install composite-action-lint"* ]]
}

@test "install_composite_action_lint warns when the GOPATH bin directory is not on PATH" {
    run_helper --separate-stderr install_composite_action_lint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${stderr}" == *"warning: ${FAKE_GOPATH}/bin is not on PATH: add it to PATH in your shell profile"* ]]
    [[ "${stderr}" == *"export PATH=\"\$(go env GOPATH)/bin:\$PATH\""* ]]
    [[ "${stderr}" != *"./install"* ]]
    [[ "${output}" != *"warning:"* ]]
}

@test "install_cscleanup creates the HOME tool manifest and installs cscleanup locally when it is missing" {
    write_dotnet_fake

    run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    _expected="dotnet new tool-manifest (in ${FAKE_HOME})
dotnet tool install Credfeto.DotNet.Repo.Formatter (in ${FAKE_HOME})"
    [ "$(calls)" = "${_expected}" ]
    [[ "${output}" != *"warning:"* ]]
}

@test "install_cscleanup updates cscleanup in the existing HOME tool manifest when it is installed" {
    write_dotnet_fake
    mkdir -p "${FAKE_HOME}/.config"
    : > "${FAKE_HOME}/.config/dotnet-tools.json"

    FAKE_DOTNET_TOOLS="credfeto.dotnet.repo.formatter 1.0.0 cscleanup ${FAKE_HOME}/.config/dotnet-tools.json" \
        run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(calls)" = "dotnet tool update Credfeto.DotNet.Repo.Formatter (in ${FAKE_HOME})" ]
}

@test "install_cscleanup installs cscleanup when only another package provides a cscleanup command" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    FAKE_DOTNET_TOOLS="other.formatter 1.0.0 cscleanup ${FAKE_HOME}/dotnet-tools.json" \
        run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(calls)" = "dotnet tool install Credfeto.DotNet.Repo.Formatter (in ${FAKE_HOME})" ]
}

@test "install_cscleanup skips the install when dotnet is not on PATH" {
    run_helper --separate-stderr install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${stderr}" == *"warning: dotnet not found, skipping cscleanup install"* ]]
    [[ "${output}" != *"warning:"* ]]
    [ -z "$(calls)" ]
}

@test "install_cscleanup fails when the dotnet tool install fails" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    FAKE_DOTNET_FAIL="tool install" run_helper install_cscleanup

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install Credfeto.DotNet.Repo.Formatter dotnet tool"* ]]
}

@test "install_cscleanup fails when the HOME tool manifest cannot be created" {
    write_dotnet_fake

    FAKE_DOTNET_FAIL="new tool-manifest" run_helper install_cscleanup

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install Credfeto.DotNet.Repo.Formatter dotnet tool"* ]]
    [ "$(calls)" = "dotnet new tool-manifest (in ${FAKE_HOME})" ]
}

@test "install_pwsh installs PowerShell locally, then the PSScriptAnalyzer module from HOME" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    run_helper install_pwsh

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(calls | sed -n 1p)" = "dotnet tool install PowerShell (in ${FAKE_HOME})" ]
    [[ "$(calls | sed -n 2p)" == "dotnet pwsh -NoProfile -NonInteractive -Command "*"Install-Module PSScriptAnalyzer"*"(in ${FAKE_HOME})" ]]
}

@test "install_pwsh updates PowerShell when it is already in the HOME tool manifest" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    FAKE_DOTNET_TOOLS="powershell 7.5.0 pwsh ${FAKE_HOME}/dotnet-tools.json" run_helper install_pwsh

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(calls | sed -n 1p)" = "dotnet tool update PowerShell (in ${FAKE_HOME})" ]
}

@test "install_pwsh fails, without running pwsh, when the PowerShell tool install fails" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    FAKE_DOTNET_FAIL="tool install" run_helper install_pwsh

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install PowerShell dotnet tool or PSScriptAnalyzer module"* ]]
    [[ "$(calls)" != *"dotnet pwsh "* ]]
}

@test "install_pwsh skips the install when dotnet is not on PATH" {
    run_helper --separate-stderr install_pwsh

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${stderr}" == *"warning: dotnet not found, skipping pwsh install"* ]]
    [[ "${output}" != *"warning:"* ]]
    [ -z "$(calls)" ]
}
