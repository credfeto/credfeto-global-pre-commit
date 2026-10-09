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

# Install a pipx package if missing, upgrade if already present.
#   $1 = package name
pipx_ensure() {
    pipx install "$1" 2>/dev/null || pipx upgrade "$1" || die "failed to install $1"
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

# Skipped when node is not on PATH, because nvm only puts it there once a
# version has been installed and activated.
install_npm_globals() {
    if has node; then
        info "npm global packages"
        npm install --global \
            markdownlint-cli \
            eslint \
            stylelint \
            stylelint-config-standard \
            || die "npm global install failed"
    else
        info "node not active in nvm, skipping npm global packages"
    fi
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
            warn "$gobin is not on PATH: run ./install to link composite-action-lint into ~/.local/bin,
  or add it to PATH in your shell profile (e.g. ~/.bashrc):
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
