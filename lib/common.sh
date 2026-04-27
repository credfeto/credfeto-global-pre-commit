#!/bin/bash
# Shared helpers sourced by install-deps-*.sh scripts.
# Not intended to be run directly.

die() {
    echo "$@"
    exit 1
}

has() { command -v "$1" &>/dev/null; }

# Sets ARCH_UNAME (e.g. x86_64) and ARCH_GO (e.g. amd64).
# Exits with an error on unsupported architectures.
detect_arch() {
    ARCH_UNAME=$(uname -m)
    case "$ARCH_UNAME" in
        x86_64)  ARCH_GO=amd64 ;;
        aarch64) ARCH_GO=arm64 ;;
        *)
            echo "Unsupported architecture: $ARCH_UNAME" >&2
            exit 1
            ;;
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
        echo "  $cmd already installed, skipping"
        return
    fi
    local ver
    ver=$(curl -sSf "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') \
        || die "failed to fetch $cmd version"
    local asset="${asset_tmpl//VERSION/$ver}"
    asset="${asset//ARCH/$ARCH_GO}"
    asset="${asset//UARCH/$ARCH_UNAME}"
    local url="https://github.com/${repo}/releases/download/v${ver}/${asset}"
    echo "  Installing $cmd ${ver}..."
    if [ "$binary" = "BIN" ]; then
        sudo curl -sSfL "$url" -o "/usr/local/bin/$cmd" || die "failed to download $cmd"
        sudo chmod +x "/usr/local/bin/$cmd"
    else
        curl -sSfL "$url" | sudo tar -xz -C /usr/local/bin "$binary" \
            || die "failed to install $cmd"
    fi
}

# Install or update PowerShell as a dotnet global tool.
# Skipped with a warning if dotnet is not on PATH.
install_pwsh() {
    echo "==> PowerShell (pwsh)"
    if has dotnet; then
        if dotnet tool list --global 2>/dev/null | grep -q '^powershell '; then
            dotnet tool update --global PowerShell || die "failed to update PowerShell dotnet tool"
        else
            dotnet tool install --global PowerShell || die "failed to install PowerShell dotnet tool"
        fi
        if ! echo "$PATH" | grep -q "$HOME/.dotnet/tools"; then
            echo "warning: add ~/.dotnet/tools to PATH in your shell profile (e.g. ~/.bashrc):" >&2
            echo "  export PATH=\"\$HOME/.dotnet/tools:\$PATH\"" >&2
        fi
    else
        echo "  dotnet not found — skipping pwsh install" >&2
    fi
}
