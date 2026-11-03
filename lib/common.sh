#!/bin/bash
# Shared helpers sourced by install-deps-*.sh scripts.
# Not intended to be run directly.

die() {
    if [ -t 2 ]; then
        printf '\n\033[31m✗\033[0m %s\n' "$*" >&2
    else
        printf '\n✗ %s\n' "$*" >&2
    fi
    exit 1
}

success() {
    if [ -t 1 ]; then
        printf '\n\033[32m✓\033[0m %s\n' "$*"
    else
        printf '\n✓ %s\n' "$*"
    fi
}

info() {
    if [ -t 1 ]; then
        printf '\n\033[32m→\033[0m %s\n' "$*"
    else
        printf '\n→ %s\n' "$*"
    fi
}

# info's format in yellow, on stderr, for problems that do not stop the install.
warn() {
    if [ -t 2 ]; then
        printf '\n\033[33m→\033[0m warning: %s\n' "$*" >&2
    else
        printf '\n→ warning: %s\n' "$*" >&2
    fi
}

has() { command -v "$1" &>/dev/null; }

# Sets ARCH_UNAME (e.g. x86_64) and ARCH_GO (e.g. amd64).
# Exits with an error on unsupported architectures.
detect_arch() {
    ARCH_UNAME=$(uname -m)
    case "$ARCH_UNAME" in
        x86_64)  ARCH_GO=amd64 ;;
        aarch64) ARCH_GO=arm64 ;;
        *) die "Unsupported architecture: $ARCH_UNAME" ;;
    esac
}

# Installs pipx with pip when it is not on PATH (e.g. no apt package for it).
# Installed for root, because pipx_ensure runs it through sudo, which cannot
# see a copy in this user's ~/.local/bin.
ensure_root_pipx() {
    has pipx && return 0
    sudo apt-get install -y python3-pip || die "failed to install python3-pip"
    sudo python3 -m pip install pipx || die "failed to install pipx via pip"
}

# Makes the tree at $1 readable by every user, and its directories and
# owner-executable files usable by them, as root.
make_tree_readable_by_all() {
    sudo chmod -R a+rX "$1" || die "failed to make $1 readable by all users"
}

PIPX_SHARED_HOME=/opt/pipx

# Runs pipx as root against the shared pipx home, so its apps land in
# /usr/local/bin for every account rather than in the caller's ~/.local/bin,
# which the system-wide hooks cannot reach for other users. The env-var form is
# used rather than `pipx --global`, which older pipx releases lack. sudo keeps
# the caller's umask, so 022 is set first or the venvs would be created
# unreadable by other users.
shared_pipx() {
    (
        umask 022
        sudo env PIPX_HOME="$PIPX_SHARED_HOME" PIPX_BIN_DIR=/usr/local/bin \
            PIPX_MAN_DIR=/usr/local/share/man pipx "$@"
    )
}

# Install a pipx package into the shared pipx home if missing, upgrade if
# already present. A per-user copy is never a reason to skip, because only the
# shared copy is usable by every account. The shared home is then made
# readable by all, which also repairs venvs an earlier run created under a
# restrictive umask; pipx keeps an existing venv's modes.
#   $1 = package name
pipx_ensure() {
    shared_pipx install "$1" 2>/dev/null || shared_pipx upgrade "$1" || die "failed to install $1"
    make_tree_readable_by_all "$PIPX_SHARED_HOME"
}

# Fetch the latest release tag from GitHub and install the binary to /usr/local/bin.
# Skips if the command is already installed and functional.
#   $1 = command name
#   $2 = GitHub owner/repo (e.g. rhysd/actionlint)
#   $3 = asset filename template; VERSION, ARCH (amd64/arm64), UARCH (x86_64/aarch64) substituted
#   $4 = binary name inside tar archive, or "BIN" for a direct binary download (optional; defaults to $1)
# Requires: detect_arch called beforehand (sets ARCH_GO / ARCH_UNAME).
install_github_release() {
    local cmd="$1" repo="$2" asset_tmpl="$3" binary="${4:-$1}"
    if has "$cmd" && "$cmd" --version &>/dev/null 2>&1; then
        info "$cmd already installed, skipping"
        return
    fi
    local ver
    ver=$(curl -sSf "https://api.github.com/repos/${repo}/releases/latest" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'].lstrip('v'))") \
        || die "failed to fetch $cmd version"
    local asset="${asset_tmpl//VERSION/$ver}"
    asset="${asset//UARCH/$ARCH_UNAME}"
    asset="${asset//ARCH/$ARCH_GO}"
    local url="https://github.com/${repo}/releases/download/v${ver}/${asset}"
    info "Installing $cmd ${ver}..."
    # A subshell, so the cleanup traps neither replace nor outlive any trap of
    # the script that sourced this library; die there only leaves the subshell.
    # The EXIT trap removes the temporary directory on every path out of it,
    # success included.
    (
        tmp=$(mktemp -d) || die "failed to create a temporary directory for $cmd"
        trap 'rm -rf "$tmp"' EXIT
        # Exiting runs the EXIT trap, so an interrupted download is removed too.
        trap 'exit 130' INT
        trap 'exit 143' TERM
        curl -sSfL "$url" -o "$tmp/download" || die "failed to download $cmd"
        if [ "$binary" = "BIN" ]; then
            release_binary="$tmp/download"
        else
            # Extracted as the caller rather than root, so the archive's
            # recorded owner and mode are never applied.
            mkdir "$tmp/extracted" \
                || die "failed to create the extraction directory for $cmd"
            tar -xzf "$tmp/download" -C "$tmp/extracted" "$binary" \
                || die "failed to extract $cmd"
            release_binary="$tmp/extracted/$binary"
        fi
        # install(1) sets the owner and mode itself, so neither the caller's
        # umask (which sudo keeps) nor the download can leave the binary
        # unusable by, or writable by, other users.
        sudo install -m 0755 "$release_binary" "/usr/local/bin/$cmd" \
            || die "failed to install $cmd"
    ) || exit
}

# Install the linters both platforms take from GitHub releases.
# Requires: detect_arch called beforehand (sets ARCH_UNAME), as
# install_github_release does.
install_release_linters() {
    # hadolint's release assets are named x86_64 and arm64, which neither the
    # UARCH nor the ARCH placeholder gives on both architectures, so the asset
    # name is picked per-arch here.
    local hadolint_asset
    case "$ARCH_UNAME" in
        x86_64)  hadolint_asset=hadolint-linux-x86_64 ;;
        aarch64) hadolint_asset=hadolint-linux-arm64 ;;
    esac
    install_github_release hadolint hadolint/hadolint "$hadolint_asset" BIN \
        && install_github_release dotenv-linter dotenv-linter/dotenv-linter "dotenv-linter-linux-UARCH.tar.gz" \
        && install_github_release trufflehog trufflesecurity/trufflehog "trufflehog_VERSION_linux_ARCH.tar.gz"
}

# Test-only override, so the suite never inspects the real /usr/local.
NPM_SHARED_PREFIX="${NPM_SHARED_PREFIX_TEST_OVERRIDE:-/usr/local}"

# Installs the latest Node.js LTS from the official nodejs.org tarball into the
# shared prefix, giving every account node and npm in /usr/local/bin. Used
# where the distro nodejs is older than the npm linters' engines allow. Skips
# when the shared copy is already that version and a real file; a copy
# elsewhere on PATH, or a link there into nvm's under $HOME, is never a reason
# to skip, because other users cannot run it, and the extraction replaces such
# a link. tar runs as root, which would otherwise keep the archive's owner and
# modes, so --no-same-owner and --no-same-permissions leave root ownership and
# umask 022 modes instead.
# Requires: detect_arch called beforehand (sets ARCH_UNAME).
install_shared_node() {
    local node_arch
    case "$ARCH_UNAME" in
        x86_64)  node_arch=x64 ;;
        aarch64) node_arch=arm64 ;;
    esac
    local ver
    ver=$(curl -sSf https://nodejs.org/dist/index.json \
        | python3 -c "import json,sys; print(next(r['version'] for r in json.load(sys.stdin) if r['lts']))") \
        || die "failed to fetch the latest Node.js LTS version"
    if [ ! -L "$NPM_SHARED_PREFIX/bin/node" ] \
        && [ "$("$NPM_SHARED_PREFIX/bin/node" --version 2>/dev/null)" = "$ver" ]; then
        info "Node.js $ver already installed in $NPM_SHARED_PREFIX, skipping"
        return
    fi
    local dist="node-${ver}-linux-${node_arch}"
    info "Installing Node.js $ver into $NPM_SHARED_PREFIX..."
    (
        umask 022
        tmp=$(mktemp -d) || die "failed to create a temporary directory for Node.js"
        trap 'rm -rf "$tmp"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        curl -sSfL "https://nodejs.org/dist/$ver/$dist.tar.xz" -o "$tmp/$dist.tar.xz" \
            || die "failed to download Node.js $ver"
        curl -sSfL "https://nodejs.org/dist/$ver/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt" \
            || die "failed to download the Node.js $ver checksums"
        (cd "$tmp" && grep " $dist.tar.xz\$" SHASUMS256.txt | sha256sum -c -) \
            || die "Node.js $ver download failed checksum verification"
        sudo tar -xJf "$tmp/$dist.tar.xz" -C "$NPM_SHARED_PREFIX" --strip-components=1 \
            --no-same-owner --no-same-permissions \
            "$dist/bin" "$dist/include" "$dist/lib" "$dist/share" \
            || die "failed to install Node.js $ver"
    ) || exit
}

# Installs the npm linters as root into the shared prefix, so their commands
# land in /usr/local/bin for every account rather than in the caller's nvm
# Node under $HOME, which the system-wide hooks cannot reach for other users.
# --prefix fixes where they land whichever npm sudo finds, and a per-user copy
# is never a reason to skip. --engine-strict makes a node too old for them
# fail the install rather than only warn. Package scripts are not run, because
# they would run as root. sudo keeps the caller's umask, so 022 is set first,
# and the packages are then made readable by all, which also repairs a tree an
# earlier run created under a restrictive umask.
install_npm_globals() {
    info "npm global packages (shared, $NPM_SHARED_PREFIX)"
    (
        umask 022
        sudo npm install --global --prefix "$NPM_SHARED_PREFIX" --engine-strict --ignore-scripts \
            markdownlint-cli \
            eslint \
            stylelint \
            stylelint-config-standard
    ) || die "npm global install failed"
    make_tree_readable_by_all "$NPM_SHARED_PREFIX/lib/node_modules"
}

# composite-action-lint has no package or binary release, so it needs go.
# Requires: go on PATH; callers decide what to do when it is not.
install_composite_action_lint() {
    if has composite-action-lint; then
        info "composite-action-lint already installed, skipping"
    else
        go install github.com/bettermarks/composite-action-lint/cmd/composite-action-lint@latest \
            || die "failed to install composite-action-lint"
    fi
    local gobin
    gobin="$(go env GOPATH)/bin" || die "failed to read GOPATH from go"
    case ":$PATH:" in
        *":$gobin:"*) ;;
        *)
            warn "$gobin is not on PATH: add it to PATH in your shell profile (e.g. ~/.bashrc):
  export PATH=\"\$(go env GOPATH)/bin:\$PATH\""
            ;;
    esac
}

# Install or update a dotnet tool as a *local* tool in the user's $HOME-scoped
# manifest (~/.config/dotnet-tools.json, or ~/dotnet-tools.json, whichever this
# SDK already uses/creates), creating the manifest when neither exists. Per
# ai/global/dotnet.instructions.md, dotnet tools are always invoked as
# `dotnet <toolname>` and never added to PATH; that only resolves for local
# tools, so this installs into $HOME rather than --global: the same manifest
# every other dotnet tool on this machine already uses, giving
# `dotnet <toolname>` resolution from any repo under $HOME without a per-repo
# manifest. Runs in a subshell so the caller's working directory is unchanged,
# and returns non-zero on failure for the caller to report.
#   $1 = package ID (e.g. PowerShell)
#   $2 = command the package provides (e.g. pwsh)
# Requires: dotnet on PATH.
install_home_dotnet_tool() {
    (
        cd "$HOME" || exit 1
        if [ ! -f dotnet-tools.json ] && [ ! -f .config/dotnet-tools.json ]; then
            dotnet new tool-manifest || exit 1
        fi
        if dotnet tool list 2>/dev/null \
            | awk -v pkg="$1" -v cmd="$2" \
                'tolower($3)==tolower(cmd) && tolower($1)==tolower(pkg){found=1} END{exit !found}'; then
            dotnet tool update "$1"
        else
            dotnet tool install "$1"
        fi
    )
}

# Install or update PowerShell as a local dotnet tool (see
# install_home_dotnet_tool), plus the PSScriptAnalyzer module it needs, which
# is installed by the pwsh resolved from $HOME's manifest.
# Skipped with a warning if dotnet is not on PATH.
install_pwsh() {
    info "PowerShell (pwsh, local dotnet tool)"
    if has dotnet; then
        (
            install_home_dotnet_tool PowerShell pwsh || exit 1
            cd "$HOME" || exit 1
            dotnet pwsh -NoProfile -NonInteractive -Command \
                "if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -ErrorAction Stop }"
        ) || die "failed to install PowerShell dotnet tool or PSScriptAnalyzer module"
    else
        warn "dotnet not found, skipping pwsh install"
    fi
}

# Install or update the cscleanup C# formatter (Credfeto.DotNet.Repo.Formatter)
# as a local dotnet tool (see install_home_dotnet_tool), which is how
# run-formatter invokes it (`dotnet cscleanup`).
# Skipped with a warning if dotnet is not on PATH.
install_cscleanup() {
    info "cscleanup (Credfeto.DotNet.Repo.Formatter, local dotnet tool)"
    if has dotnet; then
        install_home_dotnet_tool Credfeto.DotNet.Repo.Formatter cscleanup \
            || die "failed to install Credfeto.DotNet.Repo.Formatter dotnet tool"
    else
        warn "dotnet not found, skipping cscleanup install"
    fi
}
