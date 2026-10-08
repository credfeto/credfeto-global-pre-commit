#!/usr/bin/env bats
# Acceptance tests for install_github_release in lib/common.sh: a direct
# binary download into /usr/local/bin through sudo must not inherit the
# caller's restrictive umask, and must end up executable by every user.
#
# Never runs real sudo or touches /usr/local/bin: sudo and curl are fakes on
# PATH, sudo only runs its "sh -c" download wrapper and records every call.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${FAKE_BIN}"

    cat > "${FAKE_BIN}/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_SUDO_LOG"
case "$1" in
    sh) exec "$@" ;;
    chmod) [ -z "${FAKE_SUDO_FAIL_CHMOD:-}" ] || exit 1 ;;
esac
exit 0
EOF

    cat > "${FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
case " $* " in
    *" -o "*)
        [ -z "${FAKE_CURL_FAIL_DOWNLOAD:-}" ] || exit 1
        umask > "$FAKE_DOWNLOAD_UMASK"
        ;;
    *)
        printf '{"tag_name":"v1.2.3"}'
        ;;
esac
EOF
    chmod +x "${FAKE_BIN}/sudo" "${FAKE_BIN}/curl"

    export FAKE_SUDO_LOG="${BATS_TEST_TMPDIR}/sudo.log"
    export FAKE_DOWNLOAD_UMASK="${BATS_TEST_TMPDIR}/download-umask"
    : > "${FAKE_SUDO_LOG}"
}

run_binary_install() {
    umask 027
    export PATH="${FAKE_BIN}:${TEST_PATH}"
    # shellcheck source=../lib/common.sh
    . "${REPO_DIR}/lib/common.sh"
    detect_arch
    run install_github_release fake-release-tool example/fake-release-tool "fake-release-tool-UARCH" BIN
}

@test "binary release download runs under umask 022 and is made 0755" {
    run_binary_install

    [ "${status}" -eq 0 ]
    [ "$(cat "${FAKE_DOWNLOAD_UMASK}")" = "0022" ]
    grep -Fxq "chmod 0755 /usr/local/bin/fake-release-tool" "${FAKE_SUDO_LOG}"
}

@test "binary release install dies when the download fails" {
    export FAKE_CURL_FAIL_DOWNLOAD=1

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to download fake-release-tool"* ]]
    run ! grep -q "^chmod" "${FAKE_SUDO_LOG}"
}

@test "binary release install dies when making the binary executable fails" {
    export FAKE_SUDO_FAIL_CHMOD=1

    run_binary_install

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"failed to make fake-release-tool executable"* ]]
}
