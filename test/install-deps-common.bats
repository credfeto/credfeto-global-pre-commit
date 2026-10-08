#!/usr/bin/env bats
# Acceptance tests for the install helpers in lib/common.sh shared by
# install-deps-arch and install-deps-debian: install_release_linters,
# install_npm_globals and install_composite_action_lint.
#
# Never installs anything: each helper runs in a bash whose PATH holds only
# fakes, so the host's own node, npm or go can never be found, and
# install_github_release is replaced by a function that records its arguments.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    FAKE_GOPATH="${BATS_TEST_TMPDIR}/gopath"
    mkdir -p "${FAKE_BIN}" "${FAKE_GOPATH}/bin"

    export CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
    export FAKE_GOPATH
    : > "${CALL_LOG}"

    write_logging_fake npm
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

# write_logging_fake <command>
# Writes a fake that records its arguments, and fails when FAKE_<COMMAND>_FAIL
# is set (FAKE_NPM_FAIL for npm).
write_logging_fake() {
    local _fail_var
    _fail_var="FAKE_$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')_FAIL"
    cat > "${FAKE_BIN}/$1" <<EOF
#!/bin/sh
printf '$1 %s\n' "\$*" >> "\$CALL_LOG"
[ -z "\${${_fail_var}:-}" ] || exit 1
EOF
    chmod +x "${FAKE_BIN}/$1"
}

# write_present_fake <command>
# Writes a fake that only exists, so the helper sees the command as installed.
write_present_fake() {
    printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/$1"
    chmod +x "${FAKE_BIN}/$1"
}

# run_helper <helper> [extra PATH entry]
# Sources lib/common.sh into a bash whose PATH is the fakes (plus the extra
# entry), stubs install_github_release, and runs <helper>. The stub fails for
# the tool named in FAKE_RELEASE_FAIL.
run_helper() {
    local _path="${FAKE_BIN}${2:+:$2}"
    # shellcheck disable=SC2016 # expanded by the inner bash, not here
    run env PATH="${_path}" "${BASH}" -c '
        . "$1"
        install_github_release() {
            printf "release %s\n" "$*" >> "$CALL_LOG"
            [ "$1" != "${FAKE_RELEASE_FAIL:-}" ]
        }
        "$2"
    ' _ "${REPO_DIR}/lib/common.sh" "$1"
}

calls() {
    cat "${CALL_LOG}"
}

@test "install_release_linters requests hadolint, dotenv-linter and trufflehog with their asset templates" {
    run_helper install_release_linters

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    _expected="release hadolint hadolint/hadolint hadolint-linux-UARCH BIN
release dotenv-linter dotenv-linter/dotenv-linter dotenv-linter-linux-UARCH.tar.gz
release trufflehog trufflesecurity/trufflehog trufflehog_VERSION_linux_ARCH.tar.gz"
    [ "$(calls)" = "${_expected}" ]
}

@test "install_release_linters fails, and stops, when a release install fails" {
    FAKE_RELEASE_FAIL=dotenv-linter run_helper install_release_linters

    [ "${status}" -ne 0 ] || fail_with_run_output "${status}" "${output}" "non-zero"
    grep -Fq "release dotenv-linter " "${CALL_LOG}"
    [ "$(grep -Fc "release trufflehog " "${CALL_LOG}")" -eq 0 ]
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
    run_helper install_composite_action_lint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"warning: ${FAKE_GOPATH}/bin is not on PATH"* ]]
}
