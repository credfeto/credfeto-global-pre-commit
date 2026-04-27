#!/bin/bash
# Install dependencies for credfeto-global-pre-commit on Arch Linux.
# Safe to run multiple times — pacman --needed skips already-installed packages,
# and AUR helpers with --needed do the same.
#
# Requires: an AUR helper (paru or yay) for AUR packages.
# Chaotic-AUR is supported transparently — its packages are used automatically
# if the repo is already configured.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# ── AUR helper detection ──────────────────────────────────────────────────────
if has paru; then
    AUR=paru
elif has yay; then
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
LOCALES_MISSING=0
for loc in en_GB.UTF-8 en_US.UTF-8; do
    locale -a 2>/dev/null | grep -qi "${loc//UTF-8/utf8}" || {
        sudo sed -i "s/^#\($loc\)/\1/" /etc/locale.gen
        LOCALES_MISSING=1
    }
done
if [ "$LOCALES_MISSING" -eq 1 ]; then
    sudo locale-gen || die "locale-gen failed"
fi

# ── Official repository packages ──────────────────────────────────────────────
echo "==> pacman packages"
sudo pacman -S --needed --noconfirm \
    git \
    python-pre-commit \
    shellcheck \
    yamllint \
    python-flake8 \
    python-pylint \
    ansible-lint \
    libxml2 \
    python-pipx \
    || die "pacman install failed"

# ── AUR packages ──────────────────────────────────────────────────────────────
# -bin variants are pre-compiled; Chaotic-AUR provides many of these as
# binary packages so no local compilation is needed if it is configured.
echo "==> AUR packages"
"$AUR" -S --needed --noconfirm \
    hadolint-bin \
    dotenv-linter-bin \
    sqlfluff \
    python-cfn-lint \
    || die "AUR install failed"

# ── Binary tools from GitHub releases ────────────────────────────────────────
# trufflehog-bin AUR package is broken (wrapper points to missing binary).
# actionlint-bin is not universally available in AUR.
echo "==> Binary tools from GitHub releases"
detect_arch
install_github_release actionlint rhysd/actionlint "actionlint_VERSION_linux_ARCH.tar.gz"
install_github_release trufflehog trufflesecurity/trufflehog "trufflehog_VERSION_linux_ARCH.tar.gz"

# ── pipx packages ─────────────────────────────────────────────────────────────
# python-pre-commit-hooks does not exist in AUR; pipx is the only option.
# Provides check-merge-conflict, end-of-file-fixer, check-json, etc.
echo "==> pipx packages"
pipx_ensure pre-commit-hooks

# ── npm global packages ───────────────────────────────────────────────────────
# These JS tools are best installed via npm — AUR packages lag behind upstream
# and the global npm path is already on PATH when nodejs is installed.
echo "==> npm global packages"
npm install --global \
    markdownlint-cli \
    eslint \
    stylelint \
    stylelint-config-standard \
    || die "npm global install failed"

# ── dotnet global tools ───────────────────────────────────────────────────────
install_pwsh
install_tsqllint

echo ""
echo "All dependencies installed."
echo "Run ./install.sh to register the global git hooks."
