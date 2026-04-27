#!/bin/bash
# Install dependencies for credfeto-global-pre-commit on Debian / Ubuntu.
# Safe to run multiple times — apt is idempotent, binary installs are skipped
# if the tool is already present, and pipx skips already-installed packages.
#
# Tested on Ubuntu 22.04 LTS and Debian 12 (Bookworm).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

detect_arch

# ── Locale ────────────────────────────────────────────────────────────────────
echo "==> locale"
for loc in en_GB.UTF-8 en_US.UTF-8; do
    locale -a 2>/dev/null | grep -qi "${loc//UTF-8/utf8}" \
        || sudo locale-gen "$loc" || die "locale-gen $loc failed"
done

# ── System packages ───────────────────────────────────────────────────────────
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
if ! has pipx; then
    sudo apt-get install -y python3-pip || die "failed to install python3-pip"
    python3 -m pip install --user pipx || die "failed to install pipx via pip"
    python3 -m pipx ensurepath || die "pipx ensurepath failed"
fi

# ansible-lint is in Ubuntu 22.04+ repos; fall back to pipx on older releases.
echo "==> ansible-lint"
if ! sudo apt-get install -y ansible-lint 2>/dev/null; then
    echo "  ansible-lint not in apt, installing via pipx"
    pipx_ensure ansible-lint
fi

# ── dotnet global tools ───────────────────────────────────────────────────────
install_pwsh
install_tsqllint

# ── pipx packages ─────────────────────────────────────────────────────────────
# pre-commit-hooks provides the individual check-* / end-of-file-fixer / etc.
# binaries used by the language: system hooks in .pre-commit-config.yaml.
echo "==> pipx packages"
for pkg in pre-commit-hooks sqlfluff cfn-lint; do
    pipx_ensure "$pkg"
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
if has go; then
    if ! has actionlint; then
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
