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

# Fetch the latest release tag from GitHub and install the binary to /usr/local/bin.
# Skips if the command is already installed and functional.
#   $1 = command name
#   $2 = GitHub owner/repo (e.g. rhysd/actionlint)
#   $3 = asset filename template; VERSION, ARCH (amd64/arm64), UARCH (x86_64/aarch64) substituted
#   $4 = binary name inside tar archive, or "BIN" for a direct binary download (optional; defaults to $1)
install_github_release() {
    local cmd="$1" repo="$2" asset_tmpl="$3" binary="${4:-$1}"
    if need_cmd "$cmd" && "$cmd" --version &>/dev/null 2>&1; then
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

# Detect CPU architecture for selecting the right release asset.
ARCH_UNAME=$(uname -m)
case "$ARCH_UNAME" in
    x86_64)  ARCH_GO=amd64 ;;
    aarch64) ARCH_GO=arm64 ;;
    *)
        echo "Unsupported architecture: $ARCH_UNAME" >&2
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

install_github_release hadolint hadolint/hadolint "hadolint-Linux-UARCH" BIN

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
    install_github_release actionlint rhysd/actionlint "actionlint_VERSION_linux_ARCH.tar.gz"
fi

install_github_release dotenv-linter dotenv-linter/dotenv-linter "dotenv-linter-linux-ARCH.tar.gz"
install_github_release trufflehog trufflesecurity/trufflehog "trufflehog_VERSION_linux_ARCH.tar.gz"

echo ""
echo "All dependencies installed."
echo "You may need to start a new shell for PATH changes (pipx) to take effect."
echo "Run ./install.sh to register the global git hooks."
