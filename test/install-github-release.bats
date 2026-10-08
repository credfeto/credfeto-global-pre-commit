#!/usr/bin/env bats
# Acceptance tests for install_github_release in lib/common.sh: a release is
# downloaded as the caller into a temporary directory, a tar archive is
# extracted there as the caller (so the archive's recorded owner and mode are
# never applied), the binary is installed into /usr/local/bin with an explicit
# 0755 mode (so the caller's restrictive umask, which sudo keeps, cannot leave
# it unusable by others), and the temporary directory is removed whether the
# install succeeds, fails or is interrupted.
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
if [ -n "${FAKE_CURL_RELEASE_FILE:-}" ]; then
    cat "$FAKE_CURL_RELEASE_FILE" > "$_out"
else
    printf 'fake binary' > "$_out"
fi
# Stands in for Ctrl-C mid-download: the partial file is already on disk.
[ -z "${FAKE_CURL_TERMINATE_CALLER:-}" ] || kill -TERM "$PPID"
EOF

    cat > "${FAKE_BIN}/install" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$FAKE_INSTALL_ARGS"
cat "$3" > "$FAKE_INSTALLED_CONTENT"
EOF
    chmod +x "${FAKE_BIN}/curl" "${FAKE_BIN}/install"

    RELEASE_TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${RELEASE_TMPDIR}"

    export FAKE_SUDO_LOG="${BATS_TEST_TMPDIR}/sudo.log"
    export FAKE_CURL_OUTPUT_PATH="${BATS_TEST_TMPDIR}/curl-output-path"
    export FAKE_INSTALL_ARGS="${BATS_TEST_TMPDIR}/install-args"
    export FAKE_INSTALLED_CONTENT="${BATS_TEST_TMPDIR}/installed-content"
    : > "${FAKE_SUDO_LOG}"
}

# run_release_install <asset template> [binary]
run_release_install() {
    umask 027
    export PATH="${FAKE_BIN}:${TEST_PATH}"
    export TMPDIR="${RELEASE_TMPDIR}"
    # shellcheck source=../lib/common.sh
    . "${REPO_DIR}/lib/common.sh"
    detect_arch
    run install_github_release fake-release-tool example/fake-release-tool "$@"
}

run_binary_install() {
    run_release_install "fake-release-tool-UARCH" BIN
}

run_archive_install() {
    run_release_install "fake-release-tool_VERSION_linux_ARCH.tar.gz"
}

# Builds a release archive whose binary is recorded owner-only (0700), the
# mode a root extraction would have kept.
make_release_archive() {
    local _src="${BATS_TEST_TMPDIR}/archive-src"
    mkdir -p "${_src}"
    printf 'fake archived binary' > "${_src}/fake-release-tool"
    chmod 0700 "${_src}/fake-release-tool"
    export FAKE_CURL_RELEASE_FILE="${BATS_TEST_TMPDIR}/release.tar.gz"
    tar -czf "${FAKE_CURL_RELEASE_FILE}" -C "${_src}" fake-release-tool
}

# The directory the download went into, taken from the path the fake curl was
# asked to write.
download_dir() {
    dirname "$(cat "${FAKE_CURL_OUTPUT_PATH}")"
}

# Succeeds when nothing the install created is left in its temporary directory.
release_temp_removed() {
    [ -z "$(ls -A "${RELEASE_TMPDIR}")" ]
}

@test "binary release is downloaded to a temp dir and installed 0755 by sudo install" {
    run_binary_install

    [ "${status}" -eq 0 ]
    _expected="-m 0755 $(download_dir)/download /usr/local/bin/fake-release-tool"
    [ "$(cat "${FAKE_INSTALL_ARGS}")" = "${_expected}" ]
    grep -Fxq "install ${_expected}" "${FAKE_SUDO_LOG}"
    [ "$(cat "${FAKE_INSTALLED_CONTENT}")" = "fake binary" ]
    release_temp_removed
}

@test "archive release is extracted as the caller and its binary installed 0755 by sudo install" {
    make_release_archive

    run_archive_install

    [ "${status}" -eq 0 ]
    _expected="-m 0755 $(download_dir)/extracted/fake-release-tool /usr/local/bin/fake-release-tool"
    [ "$(cat "${FAKE_INSTALL_ARGS}")" = "${_expected}" ]
    grep -Fxq "install ${_expected}" "${FAKE_SUDO_LOG}"
    run ! grep -q "^tar" "${FAKE_SUDO_LOG}"
    [ "$(cat "${FAKE_INSTALLED_CONTENT}")" = "fake archived binary" ]
    release_temp_removed
}

@test "archive release install dies and removes the temp dir when the archive cannot be extracted" {
    export FAKE_CURL_RELEASE_FILE="${BATS_TEST_TMPDIR}/not-an-archive"
    printf 'not an archive' > "${FAKE_CURL_RELEASE_FILE}"

    run_archive_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to extract fake-release-tool"* ]]
    [ ! -e "${FAKE_INSTALL_ARGS}" ]
    release_temp_removed
}

@test "archive release install dies and removes the temp dir when the extraction directory cannot be created" {
    make_release_archive
    _real_mkdir="$(command -v mkdir)"
    cat > "${FAKE_BIN}/mkdir" <<EOF
#!/bin/sh
case "\$*" in
    */extracted) exit 1 ;;
esac
exec "${_real_mkdir}" "\$@"
EOF
    chmod +x "${FAKE_BIN}/mkdir"

    run_archive_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to create the extraction directory for fake-release-tool"* ]]
    [[ "${output}" != *"failed to extract"* ]]
    [ ! -e "${FAKE_INSTALL_ARGS}" ]
    release_temp_removed
}

@test "binary release install dies and removes the temp dir when the download fails" {
    export FAKE_CURL_FAIL_DOWNLOAD=1

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to download fake-release-tool"* ]]
    [ ! -e "${FAKE_INSTALL_ARGS}" ]
    release_temp_removed
}

@test "binary release install dies and removes the temp dir when installing the binary fails" {
    export FAKE_SUDO_FAIL_COMMAND=install

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to install fake-release-tool"* ]]
    release_temp_removed
}

@test "binary release install removes the partial download when terminated mid-download" {
    export FAKE_CURL_TERMINATE_CALLER=1

    run_binary_install

    [ "${status}" -eq 143 ]
    [ ! -e "${FAKE_INSTALL_ARGS}" ]
    release_temp_removed
}

@test "binary release install dies before downloading when no temp dir can be created" {
    printf '#!/bin/sh\nexit 1\n' > "${FAKE_BIN}/mktemp"
    chmod +x "${FAKE_BIN}/mktemp"

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to create a temporary directory for fake-release-tool"* ]]
    [ ! -e "${FAKE_CURL_OUTPUT_PATH}" ]
    [ ! -e "${FAKE_INSTALL_ARGS}" ]
}
