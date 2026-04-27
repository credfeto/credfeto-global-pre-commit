#!/bin/bash
# Install dependencies for credfeto-global-pre-commit on Arch Linux.
# Safe to run multiple times — pacman --needed skips already-installed packages,
# and AUR helpers with --needed do the same.
#
# Requires: an AUR helper (paru or yay) for AUR packages.
# Chaotic-AUR is supported transparently — its packages are used automatically
# if the repo is already configured.

set -euo pipefail

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
    libxml2

# ── AUR packages ──────────────────────────────────────────────────────────────
# -bin variants are pre-compiled; Chaotic-AUR provides many of these as
# binary packages so no local compilation is needed if it is configured.
"$AUR" -S --needed --noconfirm \
    python-pre-commit-hooks \
    hadolint-bin \
    actionlint-bin \
    dotenv-linter-bin \
    trufflehog-bin \
    python-sqlfluff \
    python-cfn-lint

# ── npm global packages ───────────────────────────────────────────────────────
# These JS tools are best installed via npm — AUR packages lag behind upstream
# and the global npm path is already on PATH when nodejs is installed.
npm install --global \
    markdownlint-cli \
    eslint \
    stylelint \
    stylelint-config-standard

# ── PowerShell (dotnet global tool) ──────────────────────────────────────────
# dotnet must be installed separately (e.g. pacman -S dotnet-sdk).
# pwsh is installed as a global dotnet tool rather than the AUR powershell-bin
# so it stays on the same update channel as the rest of the .NET toolchain.
if command -v dotnet &>/dev/null; then
    if dotnet tool list --global 2>/dev/null | grep -q '^powershell '; then
        dotnet tool update --global PowerShell
    else
        dotnet tool install --global PowerShell
    fi
else
    echo "warning: dotnet not found — skipping pwsh install (install dotnet-sdk first)" >&2
fi

echo ""
echo "All dependencies installed."
echo "Run ./install.sh to register the global git hooks."