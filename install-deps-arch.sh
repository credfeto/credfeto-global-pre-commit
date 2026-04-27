#!/bin/bash
# Install dependencies for credfeto-global-pre-commit on Arch Linux.
# Safe to run multiple times — pacman --needed skips already-installed packages,
# and AUR helpers with --needed do the same.
#
# Requires: an AUR helper (paru or yay) for AUR packages.
# Chaotic-AUR is supported transparently — its packages are used automatically
# if the repo is already configured.

set -euo pipefail

die() {
    echo "$@"
    exit 1
}

# ── AUR helper detection ──────────────────────────────────────────────────────
if command -v paru &>/dev/null; then
    AUR=paru
elif command -v yay &>/dev/null; then
    AUR=yay
else
    cat >&2 <<'EOF'
error: no AUR helper found (paru or yay required)

Install paru (recommended):
  sudo pacman -S --needed base-devel git
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  cd /tmp/paru && makepkg -si

Install yay:
  sudo pacman -S --needed base-devel git
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay && makepkg -si
EOF
    exit 1
fi

echo "Using AUR helper: $AUR"

# ── Locale ────────────────────────────────────────────────────────────────────
LOCALES_NEEDED="en_GB.UTF-8 en_US.UTF-8"
LOCALES_MISSING=0
for loc in $LOCALES_NEEDED; do
    locale -a 2>/dev/null | grep -qi "${loc//UTF-8/utf8}" || {
        sudo sed -i "s/^#\($loc\)/\1/" /etc/locale.gen
        LOCALES_MISSING=1
    }
done
if [ "$LOCALES_MISSING" -eq 1 ]; then
    sudo locale-gen || die "locale-gen failed"
fi

# ── Official repository packages ──────────────────────────────────────────────
# These are all in the Arch extra/community repos.
sudo pacman -S --needed --noconfirm \
    git \
    python-pre-commit \
    shellcheck \
    yamllint \
    python-flake8 \
    python-pylint \
    ansible-lint \
    libxml2 \
    || die "pacman install failed"

# ── AUR packages ──────────────────────────────────────────────────────────────
# -bin variants are pre-compiled; Chaotic-AUR provides many of these as
# binary packages so no local compilation is needed if it is configured.
"$AUR" -S --needed --noconfirm \
    hadolint-bin \
    dotenv-linter-bin \
    sqlfluff \
    python-cfn-lint \
    || die "AUR install failed"

# ── Binary tools from GitHub releases ────────────────────────────────────────
# trufflehog-bin AUR package is broken (wrapper points to missing binary).
# actionlint-bin is not universally available in AUR.
ARCH_GO=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

if ! command -v actionlint &>/dev/null; then
    ACTIONLINT_VER=$(curl -sSf https://api.github.com/repos/rhysd/actionlint/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') \
        || die "failed to fetch actionlint version"
    curl -sSfL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VER}/actionlint_${ACTIONLINT_VER}_linux_${ARCH_GO}.tar.gz" \
        | sudo tar -xz -C /usr/local/bin actionlint \
        || die "failed to install actionlint"
fi

if ! command -v trufflehog &>/dev/null || [ ! -x "$(command -v trufflehog)" ] || ! trufflehog --version &>/dev/null; then
    TRUFFLEHOG_VER=$(curl -sSf https://api.github.com/repos/trufflesecurity/trufflehog/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v') \
        || die "failed to fetch trufflehog version"
    curl -sSfL "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VER}/trufflehog_${TRUFFLEHOG_VER}_linux_${ARCH_GO}.tar.gz" \
        | sudo tar -xz -C /usr/local/bin trufflehog \
        || die "failed to install trufflehog"
fi

# ── pipx packages ─────────────────────────────────────────────────────────────
# python-pre-commit-hooks does not exist in AUR; pipx is the only option.
# Provides check-merge-conflict, end-of-file-fixer, check-json, etc.
sudo pacman -S --needed --noconfirm python-pipx || die "failed to install python-pipx"
pipx install pre-commit-hooks 2>/dev/null || pipx upgrade pre-commit-hooks || die "failed to install pre-commit-hooks"

# ── npm global packages ───────────────────────────────────────────────────────
# These JS tools are best installed via npm — AUR packages lag behind upstream
# and the global npm path is already on PATH when nodejs is installed.
npm install --global \
    markdownlint-cli \
    eslint \
    stylelint \
    stylelint-config-standard \
    || die "npm global install failed"

# ── PowerShell (dotnet global tool) ──────────────────────────────────────────
# dotnet must be installed separately (e.g. pacman -S dotnet-sdk).
# pwsh is installed as a global dotnet tool rather than the AUR powershell-bin
# so it stays on the same update channel as the rest of the .NET toolchain.
if command -v dotnet &>/dev/null; then
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
    echo "warning: dotnet not found — skipping pwsh install (install dotnet-sdk first)" >&2
fi

echo ""
echo "All dependencies installed."
echo "Run ./install.sh to register the global git hooks."
