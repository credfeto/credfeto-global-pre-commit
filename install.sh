#!/bin/sh
# Configure git globally to use the hooks in this repo.
# Run once after cloning.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$REPO_DIR/hooks"
SCRIPTS_DIR="$REPO_DIR/scripts"

chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push"
chmod +x "$SCRIPTS_DIR/buildtest" "$SCRIPTS_DIR/buildcheck"
chmod +x "$SCRIPTS_DIR/check-case-sensitivity" "$SCRIPTS_DIR/check-ignored-files"
chmod +x "$SCRIPTS_DIR/check-merge-commits" "$SCRIPTS_DIR/check-merge-conflicts"
chmod +x "$SCRIPTS_DIR/check-secrets"

git config --global core.hooksPath "$HOOKS_DIR"

echo "Global git hooks installed from: $HOOKS_DIR"
