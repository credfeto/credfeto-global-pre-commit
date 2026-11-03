#!/usr/bin/env bats
# Acceptance tests for the install helpers in lib/common.sh shared by
# install-deps-arch and install-deps-debian: install_release_linters,
# install_shared_node, install_npm_globals, install_composite_action_lint,
# install_pwsh, install_cscleanup, ensure_root_pipx and pipx_ensure.
#
# Never installs anything: each helper runs in a bash whose PATH holds only
# fakes, so the host's own node, npm, go or dotnet can never be found, the
# shared npm prefix is a per-test directory,
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
    link_host_tool awk "${FAKE_BIN}"
}

# write_pipx_fakes
# Writes a fake sudo (see write_fake_sudo) that records each call, a fake pipx
# that records its arguments, the pipx location variables it sees and its
# umask, and a fake chmod that only records, so nothing is ever written to the
# shared pipx home. pipx fails the subcommands listed in FAKE_PIPX_FAIL
# (e.g. "install upgrade"); chmod fails when FAKE_CHMOD_FAIL is set.
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
exit 0
EOF
    chmod +x "${FAKE_BIN}/pipx"
    write_chmod_fake
    link_host_tool env "${FAKE_BIN}"
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
        mkdir -p "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin"
        printf '#!/bin/sh\necho %s\n' "$1" > "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin/node"
        chmod +x "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin/node"
    fi
    local _tool
    for _tool in python3 mktemp rm grep sha256sum cut dirname; do
        link_host_tool "${_tool}" "${FAKE_BIN}" || return 1
    done
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
    local _nvm_bin="${FAKE_HOME}/.nvm/versions/node/v24.2.0/bin"
    mkdir -p "${_nvm_bin}"
    printf '#!/bin/sh\nexit 0\n' > "${_nvm_bin}/eslint"
    "$(type -P chmod)" +x "${_nvm_bin}/eslint"

    run_helper install_npm_globals "${_nvm_bin}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"--ignore-scripts markdownlint-cli eslint stylelint stylelint-config-standard umask=0022 root=1"* ]] \
        || fail_test "shared install not run: $(calls)"
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
    local _nvm_bin="${FAKE_HOME}/.nvm/versions/node/v24.2.0/bin"
    mkdir -p "${_nvm_bin}"
    printf '#!/bin/sh\necho v24.2.0\n' > "${_nvm_bin}/node"
    "$(type -P chmod)" +x "${_nvm_bin}/node"

    ARCH_UNAME=x86_64 run_helper install_shared_node "${_nvm_bin}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"tar -xJf "* ]] || fail_test "shared node not installed: $(calls)"
}

@test "install_shared_node replaces a shared node that links to the latest LTS under HOME" {
    write_node_fakes ""
    local _nvm_bin="${FAKE_HOME}/.nvm/versions/node/v24.2.0/bin"
    mkdir -p "${_nvm_bin}" "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin"
    printf '#!/bin/sh\necho v24.2.0\n' > "${_nvm_bin}/node"
    "$(type -P chmod)" +x "${_nvm_bin}/node"
    ln -s "${_nvm_bin}/node" "${NPM_SHARED_PREFIX_TEST_OVERRIDE}/bin/node"

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
    printf '#!/bin/sh\nexit 1\n' > "${FAKE_BIN}/mktemp"
    chmod +x "${FAKE_BIN}/mktemp"

    ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to create a temporary directory for Node.js"* ]]
    [[ "$(calls)" != *".tar.xz"* ]]
    [[ "$(calls)" != *"tar "* ]]
}

@test "install_shared_node removes its temporary directory" {
    write_node_fakes ""
    export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${TMPDIR}"

    ARCH_UNAME=x86_64 run_helper install_shared_node

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ -z "$(ls -A "${TMPDIR}")" ] || fail_test "temporary files left: $(ls -A "${TMPDIR}")"
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

@test "pipx_ensure installs into the shared pipx home as root with umask 022, then opens it to all users" {
    write_pipx_fakes

    umask 077
    run_helper pipx_ensure "" pre-commit-hooks
    umask 022

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _expected
    _expected="env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install pre-commit-hooks
pipx install pre-commit-hooks PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man umask=0022 root=1
chmod -R a+rX /opt/pipx
chmod -R a+rX /opt/pipx root=1"
    [ "$(calls)" = "${_expected}" ] || fail_test "unexpected calls: $(calls)"
}

@test "pipx_ensure installs the shared copy even when a per-user copy is already on PATH" {
    write_pipx_fakes
    mkdir -p "${FAKE_HOME}/.local/bin"
    printf '#!/bin/sh\nexit 0\n' > "${FAKE_HOME}/.local/bin/check-merge-conflict"
    "$(type -P chmod)" +x "${FAKE_HOME}/.local/bin/check-merge-conflict"

    run_helper pipx_ensure "${FAKE_HOME}/.local/bin" pre-commit-hooks

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"pipx install pre-commit-hooks PIPX_HOME=/opt/pipx "* ]] \
        || fail_test "shared install not run: $(calls)"
}

@test "pipx_ensure upgrades the shared copy when the install fails because it is already installed" {
    write_pipx_fakes

    FAKE_PIPX_FAIL=install run_helper pipx_ensure "" sqlfluff

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(calls)" == *"pipx upgrade sqlfluff PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man umask=0022 root=1"* ]] \
        || fail_test "shared upgrade not run: $(calls)"
    [[ "$(calls)" == *"chmod -R a+rX /opt/pipx root=1"* ]]
}

@test "pipx_ensure fails, without opening the shared home, when both install and upgrade fail" {
    write_pipx_fakes

    FAKE_PIPX_FAIL="install upgrade" run_helper pipx_ensure "" cfn-lint

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"failed to install cfn-lint"* ]]
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
