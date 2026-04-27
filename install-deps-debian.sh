#!/bin/bash
# Install dependencies for credfeto-global-pre-commit on Debian / Ubuntu.
# Safe to run multiple times — apt is idempotent, binary installs are skipped
# if the tool is already present, and pipx skips already-installed packages.
#
# Tested on Ubuntu 22.04 LTS and Debian 12 (Bookworm).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ── Helpers ───────────────────────────────────────────────────────────────────
need_cmd() { command -v "$1" &>/dev/null; }

# Install a tool binary from GitHub releases into /usr/local/bin.
# Skips the download if the command is already on PATH.
#   $1 = command name to test
#   $2 = URL (tar.gz) or direct binary URL (no extension)
#   $3 = "bin"    → direct binary download
#        "tar"    → .tar.gz; $4 = binary name inside archive
#        "tgz"    → alias for tar
install_github_bin() {
    local cmd="$1" url="$2" mode="${3:-bin}" inner="${4:-$1}"
    if need_cmd "$cmd"; then
        echo "  $cmd already installed, skipping"
        return
    fi
    echo "  Installing $cmd from $url …"
    case "$mode" in
        bin)
            curl -sSfL "$url" -o "/usr/local/bin/$cmd"
            chmod +x "/usr/local/bin/$cmd"
            ;;
        tar|tgz)
            curl -sSfL "$url" | tar -xz -C /usr/local/bin "$inner"
            chmod +x "/usr/local/bin/$inner"
            ;;
    esac
}

# Detect CPU architecture for selecting the right release asset.
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_GO=amd64 ;;
    aarch64) ARCH_GO=arm64 ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

# ── System packages ───────────────────────────────────────────────────────────
echo "==> apt packages"
sudo apt-get update -qq
sudo apt-get install -y \
    git \
    pre-commit \
    shellcheck \
    yamllint \
    python3-flake8 \
    python3-pylint \
    libxml2-utils \
    curl \
    gpg \
    pipx

# Ensure pipx is available even on older systems that lack the apt package.
if ! need_cmd pipx; then
    sudo apt-get install -y python3-pip
    python3 -m pip install --user pipx
    python3 -m pipx ensurepath
fi

# ansible-lint is in Ubuntu 22.04+ repos; fall back to pipx on older releases.
echo "==> ansible-lint"
if ! sudo apt-get install -y ansible-lint 2>/dev/null; then
    echo "  ansible-lint not in apt, installing via pipx"
    pipx install ansible-lint 2>/dev/null || pipx upgrade ansible-lint
fi

# ── PowerShell (dotnet global tool) ───────────────────────────────────────────
echo "==> PowerShell (pwsh)"
if need_cmd dotnet; then
    if dotnet tool list --global 2>/dev/null | grep -q '^powershell '; then
        dotnet tool update --global PowerShell
    else
        dotnet tool install --global PowerShell
    fi
else
    echo "  dotnet not found — skipping pwsh install" >&2
fi

# ── pipx packages ─────────────────────────────────────────────────────────────
# pre-commit-hooks provides the individual check-* / end-of-file-fixer / etc.
# binaries used by the language: system hooks in .pre-commit-config.yaml.
echo "==> pipx packages"
for pkg in pre-commit-hooks sqlfluff cfn-lint; do
    pipx install "$pkg" 2>/dev/null || pipx upgrade "$pkg"
done

# Ensure ~/.local/bin is on PATH for this session (pipx installs land there).
export PATH="$HOME/.local/bin:$PATH"

# ── npm global packages ───────────────────────────────────────────────────────
echo "==> npm global packages"
npm install --global \
    markdownlint-cli \
    eslint \
    stylelint \
    stylelint-config-standard

# ── Binary releases from GitHub ───────────────────────────────────────────────
# These tools have no Debian package; binaries are downloaded from GitHub
# releases and installed to /usr/local/bin.
echo "==> Binary tools from GitHub releases"

# hadolint — single static binary
install_github_bin hadolint \
    "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-$(uname -m)" \
    bin

# actionlint — tar.gz release
ACTIONLINT_VER=$(curl -sSf https://api.github.com/repos/rhysd/actionlint/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v')
install_github_bin actionlint \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VER}/actionlint_${ACTIONLINT_VER}_linux_${ARCH_GO}.tar.gz" \
    tar actionlint

# dotenv-linter — tar.gz release
DOTENV_VER=$(curl -sSf https://api.github.com/repos/dotenv-linter/dotenv-linter/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v')
install_github_bin dotenv-linter \
    "https://github.com/dotenv-linter/dotenv-linter/releases/download/v${DOTENV_VER}/dotenv-linter-linux-${ARCH_GO}.tar.gz" \
    tar dotenv-linter

# trufflehog — tar.gz release
TRUFFLEHOG_VER=$(curl -sSf https://api.github.com/repos/trufflesecurity/trufflehog/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v')
install_github_bin trufflehog \
    "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VER}/trufflehog_${TRUFFLEHOG_VER}_linux_${ARCH_GO}.tar.gz" \
    tar trufflehog

echo ""
echo "All dependencies installed."
echo "You may need to start a new shell for PATH changes (pipx) to take effect."
echo "Run ./install.sh to register the global git hooks."