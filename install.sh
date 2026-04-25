#!/bin/sh
# Configure git globally to use the hooks in this repo.
# Run once after cloning.

HOOKS_DIR="$(cd "$(dirname "$0")/hooks" && pwd)"

chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push"
git config --global core.hooksPath "$HOOKS_DIR"

echo "Global git hooks installed from: $HOOKS_DIR"
echo "All commits and pushes are now blocked in this environment."
