#!/usr/bin/env bats
# Acceptance tests for install_github_release in lib/common.sh: a direct
# binary download is fetched as the caller into a temporary file, installed
# into /usr/local/bin with an explicit 0755 mode (so the caller's restrictive
# umask, which sudo keeps, cannot leave it unusable by others), and the
# temporary file is removed whether or not the install succeeds.
#
# Never runs real sudo or touches /usr/local/bin: sudo, curl and install are
# fakes on PATH, and the fake install only records what it was asked to do.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    write_fake_sudo "${FAKE_BIN}"

    cat > "${FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
_out=""
while [ $# -gt 0 ]; do
    [ "$1" = -o ] && _out="$2"
    shift
done
if [ -z "$_out" ]; then
    printf '{"tag_name":"v1.2.3"}'
    exit 0
fi
printf '%s' "$_out" > "$FAKE_CURL_OUTPUT_PATH"
[ -z "${FAKE_CURL_FAIL_DOWNLOAD:-}" ] || exit 1
printf 'fake binary' > "$_out"
EOF

    cat > "${FAKE_BIN}/install" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$FAKE_INSTALL_ARGS"
cat "$3" > "$FAKE_INSTALLED_CONTENT"
EOF
    chmod +x "${FAKE_BIN}/curl" "${FAKE_BIN}/install"

    export FAKE_SUDO_LOG="${BATS_TEST_TMPDIR}/sudo.log"
    export FAKE_CURL_OUTPUT_PATH="${BATS_TEST_TMPDIR}/curl-output-path"
    export FAKE_INSTALL_ARGS="${BATS_TEST_TMPDIR}/install-args"
    export FAKE_INSTALLED_CONTENT="${BATS_TEST_TMPDIR}/installed-content"
    : > "${FAKE_SUDO_LOG}"
}

run_binary_install() {
    umask 027
    export PATH="${FAKE_BIN}:${TEST_PATH}"
    export TMPDIR="${BATS_TEST_TMPDIR}"
    # shellcheck source=../lib/common.sh
    . "${REPO_DIR}/lib/common.sh"
    detect_arch
    run install_github_release fake-release-tool example/fake-release-tool "fake-release-tool-UARCH" BIN
}

# Succeeds when the temporary file the fake curl was asked to write is gone.
download_temp_file_removed() {
    local _tmp
    _tmp=$(cat "${FAKE_CURL_OUTPUT_PATH}")
    [ -n "${_tmp}" ] && [ ! -e "${_tmp}" ]
}

@test "binary release is downloaded to a temp file and installed 0755 by sudo install" {
    run_binary_install

    [ "${status}" -eq 0 ]
    _tmp=$(cat "${FAKE_CURL_OUTPUT_PATH}")
    grep -Fxq "install -m 0755 ${_tmp} /usr/local/bin/fake-release-tool" "${FAKE_SUDO_LOG}"
    [ "$(cat "${FAKE_INSTALLED_CONTENT}")" = "fake binary" ]
    download_temp_file_removed
}

@test "binary release install dies and removes the temp file when the download fails" {
    export FAKE_CURL_FAIL_DOWNLOAD=1

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to download fake-release-tool"* ]]
    run ! grep -q "^install" "${FAKE_SUDO_LOG}"
    download_temp_file_removed
}

@test "binary release install dies and removes the temp file when installing the binary fails" {
    export FAKE_SUDO_FAIL_COMMAND=install

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to install fake-release-tool"* ]]
    download_temp_file_removed
}

@test "binary release install dies before downloading when no temp file can be created" {
    printf '#!/bin/sh\nexit 1\n' > "${FAKE_BIN}/mktemp"
    chmod +x "${FAKE_BIN}/mktemp"

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to create a temporary file for fake-release-tool"* ]]
    [ ! -e "${FAKE_CURL_OUTPUT_PATH}" ]
    run ! grep -q "^install" "${FAKE_SUDO_LOG}"
}
