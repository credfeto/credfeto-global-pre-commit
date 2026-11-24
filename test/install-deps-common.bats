#!/usr/bin/env bats
# Acceptance tests for the install helpers in lib/common.sh shared by
# install-deps-arch and install-deps-debian: install_release_linters,
# install_shared_node, install_shared_actionlint, install_npm_globals,
# install_composite_action_lint, install_cscleanup, ensure_root_pipx and
# pipx_ensure.
#
# Never installs anything: each helper runs in a bash whose PATH holds only
# fakes, so the host's own node, npm, go or dotnet can never be found, the
# shared npm prefix, dotnet tool path and bin directory are per-test
# directories,
# install_github_release is replaced by a function that records its arguments,
# and HOME is a per-test directory, so the host's own dotnet tool manifest is
# never seen.

load test_helper

bats_require_minimum_version 1.5.0

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
    FAKE_GOPATH="${BATS_TEST_TMPDIR}/gopath"
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    # Where an nvm-managed Node.js and its global npm packages live under HOME.
    NVM_BIN="${FAKE_HOME}/.nvm/versions/node/v24.2.0/bin"
    mkdir -p "${FAKE_BIN}" "${FAKE_GOPATH}/bin" "${FAKE_HOME}"

    export CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
    export FAKE_GOPATH
    export NPM_SHARED_PREFIX_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/usr/local"
    : > "${CALL_LOG}"

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

# write_install_fake
# Writes a fake install(1) for `install -m <mode> <source> <destination>` that
# records its arguments and whether it runs as root, then copies the source to
# the destination, so a test can inspect what was installed.
write_install_fake() {
    cat > "${FAKE_BIN}/install" <<'EOF'
#!/bin/sh
printf 'install %s root=%s\n' "$*" "${FAKE_SUDO_AS_ROOT:-}" >> "$CALL_LOG"
cat "$3" > "$4"
EOF
    "$(type -P chmod)" +x "${FAKE_BIN}/install"
    link_host_tool cat "${FAKE_BIN}"
}

# write_dotnet_fake
# Writes a fake dotnet. `dotnet tool list` prints the column headings and then
# FAKE_DOTNET_TOOLS (one "<package> <version> <command> <manifest>" row per
# line); `dotnet tool list --tool-path <dir>` prints FAKE_SHARED_DOTNET_TOOLS
# (one "<package> <version> <command>" row per line) instead. Every other call
# is recorded with the directory it ran in, and, when run through sudo, with
# root=1 and its umask; it fails when its arguments start with FAKE_DOTNET_FAIL
# (e.g. "tool install"). Also writes the fakes the shared install needs: a
# recording sudo, chmod (see write_chmod_fake) and install (see
# write_install_fake), and sets the shared tool path and bin directory to
# per-test directories.
write_dotnet_fake() {
    cat > "${FAKE_BIN}/dotnet" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "tool list" ]; then
    printf 'Package Id      Version      Commands      Manifest\n'
    printf -- '----------------------------------------------------\n'
    if [ "${3:-}" = "--tool-path" ]; then
        [ -z "${FAKE_SHARED_DOTNET_TOOLS:-}" ] || printf '%s\n' "$FAKE_SHARED_DOTNET_TOOLS"
    else
        [ -z "${FAKE_DOTNET_TOOLS:-}" ] || printf '%s\n' "$FAKE_DOTNET_TOOLS"
    fi
    exit 0
fi
if [ -n "${FAKE_SUDO_AS_ROOT:-}" ]; then
    printf 'dotnet %s root=1 umask=%s\n' "$*" "$(umask)" >> "$CALL_LOG"
else
    printf 'dotnet %s (in %s)\n' "$*" "$PWD" >> "$CALL_LOG"
fi
case "$*" in
    "${FAKE_DOTNET_FAIL:-no failure requested}"*) exit 1 ;;
esac
exit 0
EOF
    chmod +x "${FAKE_BIN}/dotnet"
    # The installed-tool check pipes `dotnet tool list` through awk, which the
    # fakes-only PATH would otherwise hide.
    link_host_tool awk "${FAKE_BIN}"
    write_fake_sudo "${FAKE_BIN}"
    write_chmod_fake
    write_install_fake
    link_host_tool mktemp "${FAKE_BIN}"
    link_host_tool rm "${FAKE_BIN}"
    export DOTNET_SHARED_TOOLS_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/opt/dotnet-tools"
    export SHARED_BIN_DIR_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/usr/local/bin"
    mkdir -p "${SHARED_BIN_DIR_TEST_OVERRIDE}"
}

# home_dotnet_calls
# Prints the recorded dotnet calls made as the caller, for the $HOME manifest.
home_dotnet_calls() {
    grep -v ' root=' "${CALL_LOG}"
}

# write_pipx_fakes
# Writes a fake sudo (see write_fake_sudo) that records each call, a fake pipx
# that records its arguments, the pipx location variables it sees and its
# umask, and a fake chmod that only records, so nothing is ever written to the
# shared pipx home. pipx fails the subcommands listed in FAKE_PIPX_FAIL
# (e.g. "install upgrade"); chmod fails when FAKE_CHMOD_FAIL is set.
# `pipx list --short` prints FAKE_PIPX_INSTALLED (one "<package> <version>"
# row per line), the packages already in the shared pipx home.
write_pipx_fakes() {
    write_fake_sudo "${FAKE_BIN}"
    export FAKE_SUDO_LOG="${CALL_LOG}"
    cat > "${FAKE_BIN}/pipx" <<'EOF'
#!/bin/sh
printf 'pipx %s PIPX_HOME=%s PIPX_BIN_DIR=%s PIPX_MAN_DIR=%s umask=%s root=%s\n' \
    "$*" "${PIPX_HOME:-}" "${PIPX_BIN_DIR:-}" "${PIPX_MAN_DIR:-}" "$(umask)" "${FAKE_SUDO_AS_ROOT:-}" \
    >> "$CALL_LOG"
case " ${FAKE_PIPX_FAIL:-} " in
    *" $1 "*) exit 1 ;;
esac
if [ "$*" = "list --short" ] && [ -n "${FAKE_PIPX_INSTALLED:-}" ]; then
    printf '%s\n' "$FAKE_PIPX_INSTALLED"
fi
exit 0
EOF
    chmod +x "${FAKE_BIN}/pipx"
    write_chmod_fake
    link_host_tool env "${FAKE_BIN}"
    # The installed-package check pipes `pipx list --short` through awk, which
    # the fakes-only PATH would otherwise hide.
    link_host_tool awk "${FAKE_BIN}"
}

# write_chmod_fake
# Writes a fake chmod that only records its arguments and whether it runs as
# root, failing when FAKE_CHMOD_FAIL is set.
write_chmod_fake() {
    cat > "${FAKE_BIN}/chmod" <<'EOF'
#!/bin/sh
printf 'chmod %s root=%s\n' "$*" "${FAKE_SUDO_AS_ROOT:-}" >> "$CALL_LOG"
[ -z "${FAKE_CHMOD_FAIL:-}" ]
EOF
    "$(type -P chmod)" +x "${FAKE_BIN}/chmod"
}

# write_npm_fakes
# Writes a fake sudo that records each call, a fake npm that records its
# arguments, its umask and whether it runs as root, failing when FAKE_NPM_FAIL
# is set, and a recording chmod (see write_chmod_fake).
write_npm_fakes() {
    write_fake_sudo "${FAKE_BIN}"
    export FAKE_SUDO_LOG="${CALL_LOG}"
    cat > "${FAKE_BIN}/npm" <<'EOF'
#!/bin/sh
printf 'npm %s umask=%s root=%s\n' "$*" "$(umask)" "${FAKE_SUDO_AS_ROOT:-}" >> "$CALL_LOG"
[ -z "${FAKE_NPM_FAIL:-}" ]
EOF
    chmod +x "${FAKE_BIN}/npm"
    write_chmod_fake
}

# write_node_fakes <installed version>
# Writes the fakes install_shared_node needs: a recording sudo, a fake curl
# that prints a nodejs.org index whose latest LTS is v24.2.0 (after a newer
# non-LTS release) and writes a stand-in tarball and its SHASUMS256.txt for
# -o downloads, failing for a URL containing FAKE_CURL_FAIL and sending the
# signal named in FAKE_CURL_SIGNAL_CALLER to its caller after writing the
# tarball, and a fake tar
# that only records. A shared node reporting <installed version> is written
# unless it is empty. The real sha256sum checks the stand-in tarball, whose
# listed checksum is wrong when FAKE_BAD_CHECKSUM is set.
write_node_fakes() {
    write_fake_sudo "${FAKE_BIN}"
    export FAKE_SUDO_LOG="${CALL_LOG}"
    cat > "${FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
for _arg in "$@"; do
    case "$_arg" in
        https://*) _url="$_arg" ;;
    esac
done
printf 'curl %s\n' "$_url" >> "$CALL_LOG"
case "$_url" in
    *"${FAKE_CURL_FAIL:-no failure requested}"*) exit 22 ;;
esac
case "$_url" in
    */index.json)
        printf '[{"version":"v25.0.0","lts":false},{"version":"v24.2.0","lts":"Krypton"},{"version":"v22.9.0","lts":"Jod"}]\n'
        exit 0
        ;;
esac
while [ "$#" -gt 0 ]; do
    [ "$1" = "-o" ] && _out="$2"
    shift
done
case "$_url" in
    */SHASUMS256.txt)
        _sum=$(sha256sum "$(dirname "$_out")"/node-*.tar.xz | cut -d' ' -f1)
        [ -z "${FAKE_BAD_CHECKSUM:-}" ] || _sum=0000000000000000000000000000000000000000000000000000000000000000
        printf '%s  node-v24.2.0-linux-x64.tar.xz\n%s  node-v24.2.0-linux-arm64.tar.xz\n' "$_sum" "$_sum" > "$_out"
        ;;
    *)
        printf 'stand-in tarball\n' > "$_out"
        # Stands in for Ctrl-C or a kill mid-download: the partial file is
        # already on disk.
        [ -z "${FAKE_CURL_SIGNAL_CALLER:-}" ] || kill "-$FAKE_CURL_SIGNAL_CALLER" "$PPID"
        ;;
esac
EOF
    cat > "${FAKE_BIN}/tar" <<'EOF'
#!/bin/sh
printf 'tar %s root=%s umask=%s\n' "$*" "${FAKE_SUDO_AS_ROOT:-}" "$(umask)" >> "$CALL_LOG"
EOF
    chmod +x "${FAKE_BIN}/curl" "${FAKE_BIN}/tar"
    if [ -n "$1" ]; then
        write_tool "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin" node "echo $1"
    fi
    local _tool
    for _tool in python3 mktemp rm grep sha256sum cut dirname; do
        link_host_tool "${_tool}" "${FAKE_BIN}" || return 1
    done
}

# write_present_fake <command>
# Writes a fake that only exists, so the helper sees the command as installed.
write_present_fake() {
    write_tool "${FAKE_BIN}" "$1"
}

# run_helper [--separate-stderr] <helper> [extra PATH entry] [helper args...]
# Sources lib/common.sh into a bash whose PATH is the fakes (plus the extra
# entry, if not empty) and whose HOME is FAKE_HOME, stubs
# install_github_release, and runs <helper> with the helper args. The stub
# fails for the tool named in FAKE_RELEASE_FAIL.
# --separate-stderr is passed to bats' run, which then leaves stderr in
# ${stderr} instead of merging it into ${output}.
# SIGINT is reset to its default first, because bats --jobs runs tests as
# background jobs, which start with SIGINT ignored, and bash cannot trap a
# signal that was ignored when it started.
run_helper() {
    local -a _run_flags=()
    if [ "$1" = "--separate-stderr" ]; then
        _run_flags=("$1")
        shift
    fi
    local _path="${FAKE_BIN}${2:+:$2}"
    # shellcheck disable=SC2016 # expanded by the inner bash, not here
    run "${_run_flags[@]}" env --default-signal=INT PATH="${_path}" HOME="${FAKE_HOME}" "${BASH}" -c '
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
    local _expected
    _expected="release hadolint hadolint/hadolint hadolint-linux-x86_64 BIN
release dotenv-linter dotenv-linter/dotenv-linter dotenv-linter-linux-UARCH.tar.gz
release trufflehog trufflesecurity/trufflehog trufflehog_VERSION_linux_ARCH.tar.gz"
    [ "$(calls)" = "${_expected}" ]
}

@test "install_release_linters requests hadolint's arm64 asset on aarch64" {
    ARCH_UNAME=aarch64 run_helper install_release_linters

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
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

@test "install_npm_globals installs the npm linters into the shared prefix as root with umask 022, then opens them to all users" {
    write_npm_fakes
    local _prefix="${NPM_SHARED_PREFIX_TEST_OVERRIDE}"

    umask 077
    run_helper install_npm_globals
    umask 022

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
    _expected="npm install --global --prefix ${_prefix} --engine-strict --ignore-scripts markdownlint-cli eslint stylelint stylelint-config-standard
npm install --global --prefix ${_prefix} --engine-strict --ignore-scripts markdownlint-cli eslint stylelint stylelint-config-standard umask=0022 root=1
chmod -R a+rX ${_prefix}/lib/node_modules
chmod -R a+rX ${_prefix}/lib/node_modules root=1"
    [ "$(calls)" = "${_expected}" ] || fail_test "unexpected calls: $(calls)"
}

@test "install_npm_globals installs the shared copies even when per-user nvm copies are already on PATH" {
    write_npm_fakes
    write_tool "${NVM_BIN}" eslint

    run_helper install_npm_globals "${NVM_BIN}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"--ignore-scripts markdownlint-cli eslint stylelint stylelint-config-standard umask=0022 root=1"* ]] \
        || fail_test "shared install not run: $(calls)"
}

@test "install_npm_globals warns and skips, without installing, when npm is not on PATH" {
    write_fake_sudo "${FAKE_BIN}"

    FAKE_SUDO_LOG="${CALL_LOG}" run_helper install_npm_globals

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"npm not found, skipping npm global packages"* ]] \
        || fail_test "missing warning: ${output}"
    [[ "$(calls)" != *"npm install"* ]] || fail_test "npm install was run: $(calls)"
}

@test "install_npm_globals fails, without opening the shared prefix, when npm fails" {
    write_npm_fakes

    FAKE_NPM_FAIL=1 run_helper install_npm_globals

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"npm global install failed"* ]]
    [[ "$(calls)" != *"chmod"* ]]
}

@test "install_npm_globals fails when the shared packages cannot be made readable by all users" {
    write_npm_fakes

    FAKE_CHMOD_FAIL=1 run_helper install_npm_globals

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to make ${NPM_SHARED_PREFIX_TEST_OVERRIDE}/lib/node_modules readable by all users"* ]]
}

@test "install_shared_node installs the latest LTS tarball into the shared prefix as root with umask 022 on x86_64" {
    write_node_fakes ""
    local _prefix="${NPM_SHARED_PREFIX_TEST_OVERRIDE}"

    umask 077
    ARCH_UNAME=x86_64 run_helper install_shared_node
    umask 022

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"curl https://nodejs.org/dist/v24.2.0/node-v24.2.0-linux-x64.tar.xz"* ]] \
        || fail_test "tarball not downloaded: $(calls)"
    [[ "$(calls)" == *"curl https://nodejs.org/dist/v24.2.0/SHASUMS256.txt"* ]] \
        || fail_test "checksums not downloaded: $(calls)"
    [[ "$(calls)" =~ tar\ -xJf\ [^\ ]*/node-v24\.2\.0-linux-x64\.tar\.xz\ -C\ ${_prefix}\ --strip-components=1\ --no-same-owner\ --no-same-permissions\ node-v24\.2\.0-linux-x64/bin\ node-v24\.2\.0-linux-x64/include\ node-v24\.2\.0-linux-x64/lib\ node-v24\.2\.0-linux-x64/share\ root=1\ umask=0022 ]] \
        || fail_test "unexpected tar call: $(calls)"
}

@test "install_shared_node downloads the arm64 tarball on aarch64" {
    write_node_fakes ""

    ARCH_UNAME=aarch64 run_helper install_shared_node

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"curl https://nodejs.org/dist/v24.2.0/node-v24.2.0-linux-arm64.tar.xz"* ]] \
        || fail_test "arm64 tarball not downloaded: $(calls)"
    [[ "$(calls)" == *"node-v24.2.0-linux-arm64/bin "* ]]
}

@test "install_shared_node skips the install when the shared node is already the latest LTS" {
    write_node_fakes v24.2.0

    ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Node.js v24.2.0 already installed in ${NPM_SHARED_PREFIX_TEST_OVERRIDE}, skipping"* ]]
    [ "$(calls)" = "curl https://nodejs.org/dist/index.json" ] || fail_test "unexpected calls: $(calls)"
}

@test "install_shared_node upgrades an older shared node even when the latest LTS is on PATH under HOME" {
    write_node_fakes v22.9.0
    write_tool "${NVM_BIN}" node "echo v24.2.0"

    ARCH_UNAME=x86_64 run_helper install_shared_node "${NVM_BIN}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"tar -xJf "* ]] || fail_test "shared node not installed: $(calls)"
}

@test "install_shared_node replaces a shared node that links to the latest LTS under HOME" {
    write_node_fakes ""
    mkdir -p "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin"
    write_tool "${NVM_BIN}" node "echo v24.2.0"
    ln -s "${NVM_BIN}/node" "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin/node"

    ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" != *"already installed"* ]] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"tar -xJf "* ]] || fail_test "linked node not replaced: $(calls)"
}

@test "install_shared_node fails when the latest LTS version cannot be fetched" {
    write_node_fakes ""

    FAKE_CURL_FAIL=index.json ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to fetch the latest Node.js LTS version"* ]]
    [[ "$(calls)" != *"tar "* ]]
}

@test "install_shared_node fails, without installing, when the tarball download fails" {
    write_node_fakes ""

    FAKE_CURL_FAIL=.tar.xz ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to download Node.js v24.2.0"* ]]
    [[ "$(calls)" != *"tar "* ]]
}

@test "install_shared_node fails, without installing, when the checksums download fails" {
    write_node_fakes ""

    FAKE_CURL_FAIL=SHASUMS256 ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to download the Node.js v24.2.0 checksums"* ]]
    [[ "$(calls)" != *"tar "* ]]
}

@test "install_shared_node fails, without installing, when the tarball does not match its checksum" {
    write_node_fakes ""

    FAKE_BAD_CHECKSUM=1 ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"Node.js v24.2.0 download failed checksum verification"* ]]
    [[ "$(calls)" != *"tar "* ]]
}

@test "install_shared_node fails when the tarball cannot be extracted" {
    write_node_fakes ""

    FAKE_SUDO_FAIL_COMMAND=tar ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install Node.js v24.2.0"* ]]
}

# run_node_install_into_tmpdir
# Runs install_shared_node on x86_64 with TMPDIR set to a per-test directory,
# so node_temp_removed can check what it leaves behind.
run_node_install_into_tmpdir() {
    NODE_TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${NODE_TMPDIR}"
    TMPDIR="${NODE_TMPDIR}" ARCH_UNAME=x86_64 run_helper install_shared_node
}

node_temp_removed() {
    [ -z "$(ls -A "${NODE_TMPDIR}")" ] || fail_test "temporary files left: $(ls -A "${NODE_TMPDIR}")"
}

@test "install_shared_node removes the partial download when interrupted mid-download" {
    write_node_fakes ""

    FAKE_CURL_SIGNAL_CALLER=INT run_node_install_into_tmpdir

    [ "${status}" -eq 130 ] || fail_with_run_output "${status}" "${output}" 130
    [[ "$(calls)" != *"tar "* ]]
    node_temp_removed
}

@test "install_shared_node removes the partial download when terminated mid-download" {
    write_node_fakes ""

    FAKE_CURL_SIGNAL_CALLER=TERM run_node_install_into_tmpdir

    [ "${status}" -eq 143 ] || fail_with_run_output "${status}" "${output}" 143
    [[ "$(calls)" != *"tar "* ]]
    node_temp_removed
}

@test "install_shared_node dies before downloading when no temp dir can be created" {
    write_node_fakes ""
    rm "${FAKE_BIN}/mktemp"
    write_tool "${FAKE_BIN}" mktemp "exit 1"

    ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to create a temporary directory for Node.js"* ]]
    [[ "$(calls)" != *".tar.xz"* ]]
    [[ "$(calls)" != *"tar "* ]]
}

@test "install_shared_node removes its temporary directory" {
    write_node_fakes ""
    local _tmp="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${_tmp}"

    TMPDIR="${_tmp}" ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(ls -A "${_tmp}")" ] || fail_test "temporary files left: $(ls -A "${_tmp}")"
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
    local _expected
    _expected="dotnet new tool-manifest (in ${FAKE_HOME})
dotnet tool install Credfeto.DotNet.Repo.Formatter (in ${FAKE_HOME})"
    [ "$(home_dotnet_calls)" = "${_expected}" ] || fail_test "unexpected calls: $(calls)"
    [[ "${output}" != *"warning:"* ]]
}

@test "install_cscleanup updates cscleanup in the existing HOME tool manifest when it is installed" {
    write_dotnet_fake
    mkdir -p "${FAKE_HOME}/.config"
    : > "${FAKE_HOME}/.config/dotnet-tools.json"

    FAKE_DOTNET_TOOLS="credfeto.dotnet.repo.formatter 1.0.0 cscleanup ${FAKE_HOME}/.config/dotnet-tools.json" \
        run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(home_dotnet_calls)" = "dotnet tool update Credfeto.DotNet.Repo.Formatter (in ${FAKE_HOME})" ] \
        || fail_test "unexpected calls: $(calls)"
}

@test "install_cscleanup installs cscleanup when only another package provides a cscleanup command" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    FAKE_DOTNET_TOOLS="other.formatter 1.0.0 cscleanup ${FAKE_HOME}/dotnet-tools.json" \
        run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(home_dotnet_calls)" = "dotnet tool install Credfeto.DotNet.Repo.Formatter (in ${FAKE_HOME})" ] \
        || fail_test "unexpected calls: $(calls)"
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

@test "install_cscleanup installs the shared copy as root with umask 022, opens it to all users and adds a wrapper" {
    write_dotnet_fake
    local _shared="${DOTNET_SHARED_TOOLS_TEST_OVERRIDE}"
    local _wrapper="${SHARED_BIN_DIR_TEST_OVERRIDE}/cscleanup"

    umask 077
    run_helper install_cscleanup
    umask 022

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"dotnet tool install --tool-path ${_shared} Credfeto.DotNet.Repo.Formatter root=1 umask=0022"* ]] \
        || fail_test "shared install not run: $(calls)"
    [[ "$(calls)" == *"chmod -R a+rX ${_shared} root=1"* ]] || fail_test "shared tool path not opened: $(calls)"
    [[ "$(calls)" == *"/cscleanup ${_wrapper} root=1"* ]] || fail_test "wrapper not installed: $(calls)"
    local _expected_wrapper
    _expected_wrapper="#!/bin/sh
exec \"${_shared}/cscleanup\" \"\$@\""
    [ "$(cat "${_wrapper}")" = "${_expected_wrapper}" ] || fail_test "unexpected wrapper: $(cat "${_wrapper}")"
}

@test "install_cscleanup runs dotnet by its full path under sudo" {
    write_dotnet_fake

    FAKE_SUDO_LOG="${CALL_LOG}" run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"${FAKE_BIN}/dotnet tool install --tool-path ${DOTNET_SHARED_TOOLS_TEST_OVERRIDE} Credfeto.DotNet.Repo.Formatter"* ]] \
        || fail_test "dotnet not run by its full path: $(calls)"
}

@test "install_cscleanup updates, without reinstalling, a shared copy that is already installed" {
    write_dotnet_fake

    FAKE_SHARED_DOTNET_TOOLS="credfeto.dotnet.repo.formatter 1.0.0 cscleanup" run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"dotnet tool update --tool-path ${DOTNET_SHARED_TOOLS_TEST_OVERRIDE} Credfeto.DotNet.Repo.Formatter root=1 umask=0022"* ]] \
        || fail_test "shared update not run: $(calls)"
    [[ "$(calls)" != *"tool install --tool-path"* ]] || fail_test "shared install run for an installed tool: $(calls)"
}

@test "install_cscleanup installs the shared copy even when the HOME manifest already has cscleanup" {
    write_dotnet_fake
    : > "${FAKE_HOME}/dotnet-tools.json"

    FAKE_DOTNET_TOOLS="credfeto.dotnet.repo.formatter 1.0.0 cscleanup ${FAKE_HOME}/dotnet-tools.json" \
        run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"dotnet tool install --tool-path ${DOTNET_SHARED_TOOLS_TEST_OVERRIDE} Credfeto.DotNet.Repo.Formatter root=1"* ]] \
        || fail_test "shared install not run: $(calls)"
}

@test "install_cscleanup fails, without opening the shared tool path, when the shared install fails" {
    write_dotnet_fake

    FAKE_DOTNET_FAIL="tool install --tool-path" run_helper install_cscleanup

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install the shared Credfeto.DotNet.Repo.Formatter dotnet tool"* ]]
    [[ "$(calls)" != *"chmod"* ]] || fail_test "tool path opened after a failed install: $(calls)"
    [[ "$(calls)" != *"install -m"* ]] || fail_test "wrapper installed after a failed install: $(calls)"
}

@test "install_cscleanup fails, without adding the wrapper, when the shared tool path cannot be made readable by all users" {
    write_dotnet_fake

    FAKE_CHMOD_FAIL=1 run_helper install_cscleanup

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to make ${DOTNET_SHARED_TOOLS_TEST_OVERRIDE} readable by all users"* ]]
    [[ "$(calls)" != *"install -m"* ]] || fail_test "wrapper installed: $(calls)"
}

@test "install_cscleanup fails when the wrapper cannot be installed" {
    write_dotnet_fake

    FAKE_SUDO_FAIL_COMMAND=install run_helper install_cscleanup

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install the shared Credfeto.DotNet.Repo.Formatter dotnet tool"* ]]
}

@test "install_cscleanup removes the wrapper's temporary directory" {
    write_dotnet_fake
    local _tmp="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${_tmp}"

    TMPDIR="${_tmp}" run_helper install_cscleanup

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(ls -A "${_tmp}")" ] || fail_test "temporary files left: $(ls -A "${_tmp}")"
}

# write_actionlint_fakes <installed version>
# Writes the fakes install_shared_actionlint needs: a recording sudo, a fake
# curl that prints a GitHub latest-release response for v1.7.12 and writes a
# stand-in tarball and its checksums file for -o downloads, failing for a URL
# containing FAKE_CURL_FAIL, a fake tar that records its arguments and writes a
# stand-in actionlint, and a recording install (see write_install_fake). A
# shared actionlint reporting <installed version> is written unless it is
# empty. The real sha256sum checks the stand-in tarball, whose listed checksum
# is wrong when FAKE_BAD_CHECKSUM is set.
write_actionlint_fakes() {
    write_fake_sudo "${FAKE_BIN}"
    export FAKE_SUDO_LOG="${CALL_LOG}"
    export SHARED_BIN_DIR_TEST_OVERRIDE="${BATS_TEST_TMPDIR}/usr/local/bin"
    mkdir -p "${SHARED_BIN_DIR_TEST_OVERRIDE}"
    cat > "${FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
for _arg in "$@"; do
    case "$_arg" in
        https://*) _url="$_arg" ;;
    esac
done
printf 'curl %s\n' "$_url" >> "$CALL_LOG"
case "$_url" in
    *"${FAKE_CURL_FAIL:-no failure requested}"*) exit 22 ;;
    https://api.github.com/*)
        printf '{"tag_name":"v1.7.12"}\n'
        exit 0
        ;;
esac
while [ "$#" -gt 0 ]; do
    [ "$1" = "-o" ] && _out="$2"
    shift
done
case "$_url" in
    *_checksums.txt)
        _sum=$(sha256sum "$(dirname "$_out")"/actionlint_*.tar.gz | cut -d' ' -f1)
        [ -z "${FAKE_BAD_CHECKSUM:-}" ] || _sum=0000000000000000000000000000000000000000000000000000000000000000
        printf '%s  actionlint_1.7.12_darwin_amd64.tar.gz\n%s  actionlint_1.7.12_linux_amd64.tar.gz\n%s  actionlint_1.7.12_linux_arm64.tar.gz\n' \
            1111111111111111111111111111111111111111111111111111111111111111 "$_sum" "$_sum" > "$_out"
        ;;
    *)
        printf 'stand-in tarball\n' > "$_out"
        ;;
esac
EOF
    cat > "${FAKE_BIN}/tar" <<'EOF'
#!/bin/sh
printf 'tar %s root=%s\n' "$*" "${FAKE_SUDO_AS_ROOT:-}" >> "$CALL_LOG"
printf '#!/bin/sh\necho 1.7.12\n' > "$4/$5"
EOF
    "$(type -P chmod)" +x "${FAKE_BIN}/curl" "${FAKE_BIN}/tar"
    write_install_fake
    if [ -n "$1" ]; then
        write_tool "${SHARED_BIN_DIR_TEST_OVERRIDE}" actionlint "echo $1"
    fi
    local _tool
    for _tool in python3 mktemp rm grep sha256sum cut dirname head mkdir; do
        link_host_tool "${_tool}" "${FAKE_BIN}" || return 1
    done
}

@test "install_shared_actionlint installs the verified release into the shared bin directory as root on x86_64" {
    write_actionlint_fakes ""
    local _base="https://github.com/rhysd/actionlint/releases/download/v1.7.12"

    ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"curl ${_base}/actionlint_1.7.12_linux_amd64.tar.gz"* ]] \
        || fail_test "tarball not downloaded: $(calls)"
    [[ "$(calls)" == *"curl ${_base}/actionlint_1.7.12_checksums.txt"* ]] \
        || fail_test "checksums not downloaded: $(calls)"
    grep -q '^tar -xzf .*/actionlint_1\.7\.12_linux_amd64\.tar\.gz -C .*/extracted actionlint root=$' "${CALL_LOG}" \
        || fail_test "actionlint not extracted as the caller: $(calls)"
    [[ "$(calls)" == *"/extracted/actionlint ${SHARED_BIN_DIR_TEST_OVERRIDE}/actionlint root=1"* ]] \
        || fail_test "actionlint not installed as root: $(calls)"
}

@test "install_shared_actionlint downloads the arm64 tarball on aarch64" {
    write_actionlint_fakes ""

    ARCH_GO=arm64 run_helper install_shared_actionlint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"curl https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz"* ]] \
        || fail_test "arm64 tarball not downloaded: $(calls)"
}

@test "install_shared_actionlint skips the install when the shared copy is already the latest release" {
    write_actionlint_fakes 1.7.12

    ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"actionlint 1.7.12 already installed in ${SHARED_BIN_DIR_TEST_OVERRIDE}, skipping"* ]]
    [ "$(calls)" = "curl https://api.github.com/repos/rhysd/actionlint/releases/latest" ] \
        || fail_test "unexpected calls: $(calls)"
}

@test "install_shared_actionlint skips the install when the shared copy reports the latest release with a leading v" {
    write_actionlint_fakes v1.7.12

    ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"already installed"* ]] || fail_with_run_output "${status}" "${output}" 0
}

@test "install_shared_actionlint upgrades an older shared copy even when the latest release is on PATH under HOME" {
    write_actionlint_fakes 1.7.0
    write_tool "${FAKE_HOME}/go/bin" actionlint "echo v1.7.12"

    ARCH_GO=amd64 run_helper install_shared_actionlint "${FAKE_HOME}/go/bin"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"install -m 0755 "* ]] || fail_test "shared actionlint not installed: $(calls)"
}

@test "install_shared_actionlint replaces a shared copy that links to the latest release under HOME" {
    write_actionlint_fakes ""
    write_tool "${FAKE_HOME}/go/bin" actionlint "echo v1.7.12"
    ln -s "${FAKE_HOME}/go/bin/actionlint" "${SHARED_BIN_DIR_TEST_OVERRIDE}/actionlint"

    ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" != *"already installed"* ]] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"install -m 0755 "* ]] || fail_test "linked actionlint not replaced: $(calls)"
}

# Runs install_shared_actionlint under the errexit and pipefail options the
# install-deps scripts set, which run_helper does not.
run_actionlint_strict() {
    # shellcheck disable=SC2016 # expanded by the inner bash, not here
    run env --default-signal=INT PATH="${FAKE_BIN}" HOME="${FAKE_HOME}" ARCH_GO=amd64 "${BASH}" -c '
        set -euo pipefail
        . "$1"
        install_shared_actionlint
        echo "install_shared_actionlint returned"
    ' _ "${REPO_DIR}/lib/common.sh"
}

@test "install_shared_actionlint installs under errexit and pipefail when there is no shared copy" {
    write_actionlint_fakes ""

    run_actionlint_strict

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"install_shared_actionlint returned"* ]] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"install -m 0755 "* ]] || fail_test "shared actionlint not installed: $(calls)"
}

@test "install_shared_actionlint replaces a shared copy whose --version fails under errexit and pipefail" {
    write_actionlint_fakes ""
    write_tool "${SHARED_BIN_DIR_TEST_OVERRIDE}" actionlint "exit 3"

    run_actionlint_strict

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"install_shared_actionlint returned"* ]] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"install -m 0755 "* ]] || fail_test "broken shared actionlint not replaced: $(calls)"
}

@test "install_shared_actionlint fails when the latest version cannot be fetched" {
    write_actionlint_fakes ""

    FAKE_CURL_FAIL=api.github.com ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to fetch the latest actionlint version"* ]]
    [[ "$(calls)" != *"install -m"* ]] || fail_test "actionlint installed: $(calls)"
}

@test "install_shared_actionlint fails, without installing, when the tarball download fails" {
    write_actionlint_fakes ""

    FAKE_CURL_FAIL=.tar.gz ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to download actionlint 1.7.12"* ]]
    [[ "$(calls)" != *"install -m"* ]] || fail_test "actionlint installed: $(calls)"
}

@test "install_shared_actionlint fails, without installing, when the checksums download fails" {
    write_actionlint_fakes ""

    FAKE_CURL_FAIL=checksums ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to download the actionlint 1.7.12 checksums"* ]]
    [[ "$(calls)" != *"install -m"* ]] || fail_test "actionlint installed: $(calls)"
}

@test "install_shared_actionlint fails, without extracting or installing, when the tarball does not match its checksum" {
    write_actionlint_fakes ""

    FAKE_BAD_CHECKSUM=1 ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"actionlint 1.7.12 download failed checksum verification"* ]]
    [[ "$(calls)" != *"tar "* ]] || fail_test "unverified tarball extracted: $(calls)"
    [[ "$(calls)" != *"install -m"* ]] || fail_test "unverified actionlint installed: $(calls)"
}

@test "install_shared_actionlint fails when the binary cannot be installed" {
    write_actionlint_fakes ""

    FAKE_SUDO_FAIL_COMMAND=install ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install actionlint"* ]]
}

@test "install_shared_actionlint removes its temporary directory" {
    write_actionlint_fakes ""
    local _tmp="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${_tmp}"

    TMPDIR="${_tmp}" ARCH_GO=amd64 run_helper install_shared_actionlint

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(ls -A "${_tmp}")" ] || fail_test "temporary files left: $(ls -A "${_tmp}")"
}


@test "pipx_ensure installs into the shared pipx home as root with umask 022, then opens it to all users" {
    write_pipx_fakes

    umask 077
    run_helper pipx_ensure "" pre-commit-hooks
    umask 022

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
    _expected="env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx list --short
pipx list --short PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man umask=0022 root=1
env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install pre-commit-hooks
pipx install pre-commit-hooks PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man umask=0022 root=1
chmod -R a+rX /opt/pipx
chmod -R a+rX /opt/pipx root=1"
    [ "$(calls)" = "${_expected}" ] || fail_test "unexpected calls: $(calls)"
}

@test "pipx_ensure installs, without upgrading, when the shared pipx home lacks the package" {
    write_pipx_fakes

    FAKE_PIPX_INSTALLED="sqlfluff-templater-dbt 2.0.0
pre-commit 4.0.1" run_helper pipx_ensure "" sqlfluff

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"pipx install sqlfluff PIPX_HOME=/opt/pipx "* ]] \
        || fail_test "shared install not run: $(calls)"
    [[ "$(calls)" != *"pipx upgrade"* ]] || fail_test "upgrade run for a missing package: $(calls)"
}

@test "pipx_ensure installs when the shared pipx home cannot be listed" {
    write_pipx_fakes

    FAKE_PIPX_FAIL=list run_helper pipx_ensure "" sqlfluff

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"pipx install sqlfluff PIPX_HOME=/opt/pipx "* ]] \
        || fail_test "shared install not run: $(calls)"
    [[ "$(calls)" != *"pipx upgrade"* ]] || fail_test "upgrade run for an unlisted package: $(calls)"
}

@test "pipx_ensure installs the shared copy even when a per-user copy is already on PATH" {
    write_pipx_fakes
    write_tool "${FAKE_HOME}/.local/bin" check-merge-conflict

    run_helper pipx_ensure "${FAKE_HOME}/.local/bin" pre-commit-hooks

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"pipx install pre-commit-hooks PIPX_HOME=/opt/pipx "* ]] \
        || fail_test "shared install not run: $(calls)"
}

@test "pipx_ensure upgrades, without reinstalling, when the shared pipx home already has the package" {
    write_pipx_fakes

    FAKE_PIPX_INSTALLED="pre-commit-hooks 5.0.0
sqlfluff 3.0.0" run_helper pipx_ensure "" sqlfluff

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"pipx upgrade sqlfluff PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man umask=0022 root=1"* ]] \
        || fail_test "shared upgrade not run: $(calls)"
    [[ "$(calls)" != *"pipx install"* ]] || fail_test "install run for an installed package: $(calls)"
    [[ "$(calls)" == *"chmod -R a+rX /opt/pipx root=1"* ]]
}

@test "pipx_ensure fails, without opening the shared home, when the install fails" {
    write_pipx_fakes

    FAKE_PIPX_FAIL=install run_helper pipx_ensure "" cfn-lint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install cfn-lint"* ]]
    [[ "$(calls)" != *"chmod"* ]]
}

@test "pipx_ensure fails, without opening the shared home, when the upgrade of an installed package fails" {
    write_pipx_fakes

    FAKE_PIPX_INSTALLED="cfn-lint 1.0.0" FAKE_PIPX_FAIL=upgrade run_helper pipx_ensure "" cfn-lint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to upgrade cfn-lint"* ]]
    [[ "$(calls)" != *"pipx install"* ]] || fail_test "install run after a failed upgrade: $(calls)"
    [[ "$(calls)" != *"chmod"* ]]
}

@test "pipx_ensure fails when the shared pipx home cannot be made readable by all users" {
    write_pipx_fakes

    FAKE_CHMOD_FAIL=1 run_helper pipx_ensure "" pylint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to make /opt/pipx readable by all users"* ]]
}

# write_root_pipx_fakes
# Writes a fake sudo that records each call and fakes for apt-get and python3
# that only record, failing when their name is FAKE_ROOT_PIPX_FAIL.
write_root_pipx_fakes() {
    write_fake_sudo "${FAKE_BIN}"
    export FAKE_SUDO_LOG="${CALL_LOG}"
    local _tool
    for _tool in apt-get python3; do
        cat > "${FAKE_BIN}/${_tool}" <<EOF
#!/bin/sh
printf '${_tool} %s root=%s\\n' "\$*" "\${FAKE_SUDO_AS_ROOT:-}" >> "\$CALL_LOG"
[ "\${FAKE_ROOT_PIPX_FAIL:-}" != "${_tool}" ]
EOF
        chmod +x "${FAKE_BIN}/${_tool}"
    done
}

@test "ensure_root_pipx does nothing when pipx is already on PATH" {
    write_root_pipx_fakes
    write_present_fake pipx

    run_helper ensure_root_pipx

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(calls)" ] || fail_test "unexpected calls: $(calls)"
}

@test "ensure_root_pipx installs pip, then pipx with pip, as root when pipx is missing" {
    write_root_pipx_fakes

    run_helper ensure_root_pipx

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
    _expected="apt-get install -y python3-pip
apt-get install -y python3-pip root=1
python3 -m pip install pipx
python3 -m pip install pipx root=1"
    [ "$(calls)" = "${_expected}" ] || fail_test "unexpected calls: $(calls)"
}

@test "ensure_root_pipx fails, without running pip, when python3-pip cannot be installed" {
    write_root_pipx_fakes

    FAKE_ROOT_PIPX_FAIL=apt-get run_helper ensure_root_pipx

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install python3-pip"* ]]
    [[ "$(calls)" != *"python3 "* ]]
}

@test "ensure_root_pipx fails when pip cannot install pipx" {
    write_root_pipx_fakes

    FAKE_ROOT_PIPX_FAIL=python3 run_helper ensure_root_pipx

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install pipx via pip"* ]]
}
