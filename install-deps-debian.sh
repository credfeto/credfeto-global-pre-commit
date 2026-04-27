#!/bin/bash
# Install dependencies for credfeto-global-pre-commit on Debian / Ubuntu.
# Safe to run multiple times — apt is idempotent, binary installs are skipped
# if the tool is already present, and pipx skips already-installed packages.
#
# Tested on Ubuntu 22.04 LTS and Debian 12 (Bookworm).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

die() {
    echo "$@"
    exit 1
}

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
            curl -sSfL "$url" -o "/usr/local/bin/$cmd" || die "failed to download $cmd"
            chmod +x "/usr/local/bin/$cmd"
            ;;
        tar|tgz)
            curl -sSfL "$url" | tar -xz -C /usr/local/bin "$inner" || die "failed to download/extract $cmd"
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
# ── Locale ────────────────────────────────────────────────────────────────────
echo "==> locale"
for loc in en_GB.UTF-8 en_US.UTF-8; do
    locale -a 2>/dev/null | grep -qi "${loc//UTF-8/utf8}" \
        || sudo locale-gen "$loc" || die "locale-gen $loc failed"
done

echo "==> apt packages"
sudo apt-get update -qq || die "apt-get update failed"
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
    pipx \
    || die "apt-get install failed"

# Ensure pipx is available even on older systems that lack the apt package.
if ! need_cmd pipx; then
    sudo apt-get install -y python3-pip || die "failed to install python3-pip"
    python3 -m pip install --user pipx || die "failed to install pipx via pip"
    python3 -m pipx ensurepath || die "pipx ensurepath failed"
fi

# ansible-lint is in Ubuntu 22.04+ repos; fall back to pipx on older releases.
echo "==> ansible-lint"
if ! sudo apt-get install -y ansible-lint 2>/dev/null; then
    echo "  ansible-lint not in apt, installing via pipx"
    pipx install ansible-lint 2>/dev/null || pipx upgrade ansible-lint || die "failed to install ansible-lint"
fi

# ── PowerShell (dotnet global tool) ───────────────────────────────────────────
echo "==> PowerShell (pwsh)"
if need_cmd dotnet; then
    if dotnet tool list --global 2>/dev/null | grep -q '^powershell '; then
        dotnet tool update --global PowerShell || die "failed to update PowerShell dotnet tool"
    else
        dotnet tool install --global PowerShell || die "failed to install PowerShell dotnet tool"
    fi
    # dotnet global tools land in ~/.dotnet/tools — ensure it is on PATH.
    if ! echo "$PATH" | grep -q "$HOME/.dotnet/tools"; then
        echo "warning: add ~/.dotnet/tools to PATH in your shell profile (e.g. ~/.bashrc):" >&2
        echo "  export PATH=\"\$HOME/.dotnet/tools:\$PATH\"" >&2
    fi
else
    echo "  dotnet not found — skipping pwsh install" >&2
fi

# ── pipx packages ─────────────────────────────────────────────────────────────
# pre-commit-hooks provides the individual check-* / end-of-file-fixer / etc.
# binaries used by the language: system hooks in .pre-commit-config.yaml.
echo "==> pipx packages"
for pkg in pre-commit-hooks sqlfluff cfn-lint; do
    pipx install "$pkg" 2>/dev/null || pipx upgrade "$pkg" || die "failed to install $pkg"
done

# Ensure ~/.local/bin is on PATH for this session (pipx installs land there).
export PATH="$HOME/.local/bin:$PATH"

# ── npm global packages ───────────────────────────────────────────────────────
echo "==> npm global packages"
npm install --global \
    markdownlint-cli \
    eslint \
    stylelint \
    stylelint-config-standard \
    || die "npm global install failed"

# ── Binary releases from GitHub ───────────────────────────────────────────────
# These tools have no Debian package; binaries are downloaded from GitHub
# releases and installed to /usr/local/bin.
echo "==> Binary tools from GitHub releases"

# hadolint — single static binary
install_github_bin hadolint \
    "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-$(uname -m)" \
    bin

# actionlint — prefer go install, fall back to binary download
if command -v go &>/dev/null; then
    if ! need_cmd actionlint; then
        go install github.com/rhysd/actionlint/cmd/actionlint@latest || die "failed to install actionlint"
    else
        echo "  actionlint already installed, skipping"
    fi
    if ! echo "$PATH" | grep -q "${GOPATH:-$HOME/go}/bin"; then
        echo "warning: add \$GOPATH/bin to PATH in your shell profile (e.g. ~/.bashrc):" >&2
        echo "  export PATH=\"\$(go env GOPATH)/bin:\$PATH\"" >&2
    fi
else
    ACTIONLINT_VER=$(curl -sSf https://api.github.com/repos/rhysd/actionlint/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') \
        || die "failed to fetch actionlint version"
    install_github_bin actionlint \
        "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VER}/actionlint_${ACTIONLINT_VER}_linux_${ARCH_GO}.tar.gz" \
        tar actionlint
fi

# dotenv-linter — tar.gz release
DOTENV_VER=$(curl -sSf https://api.github.com/repos/dotenv-linter/dotenv-linter/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') \
    || die "failed to fetch dotenv-linter version"
install_github_bin dotenv-linter \
    "https://github.com/dotenv-linter/dotenv-linter/releases/download/v${DOTENV_VER}/dotenv-linter-linux-${ARCH_GO}.tar.gz" \
    tar dotenv-linter

# trufflehog — tar.gz release
TRUFFLEHOG_VER=$(curl -sSf https://api.github.com/repos/trufflesecurity/trufflehog/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') \
    || die "failed to fetch trufflehog version"
install_github_bin trufflehog \
    "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VER}/trufflehog_${TRUFFLEHOG_VER}_linux_${ARCH_GO}.tar.gz" \
    tar trufflehog

echo ""
echo "All dependencies installed."
echo "You may need to start a new shell for PATH changes (pipx) to take effect."
echo "Run ./install.sh to register the global git hooks."
