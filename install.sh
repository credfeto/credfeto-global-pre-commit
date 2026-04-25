#!/bin/sh
# Install global git pre-commit hooks from this repo.
# Sets core.hooksPath globally so every repo on this machine uses these hooks.
# Run once after cloning; re-run after pulling updates.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$REPO_DIR/hooks"
SCRIPTS_DIR="$REPO_DIR/scripts"

# ── Make everything executable ────────────────────────────────────────────────
chmod +x \
    "$HOOKS_DIR/pre-commit" \
    "$HOOKS_DIR/pre-push" \
    "$SCRIPTS_DIR/buildtest" \
    "$SCRIPTS_DIR/buildcheck" \
    "$SCRIPTS_DIR/check-case-sensitivity" \
    "$SCRIPTS_DIR/check-ignored-files" \
    "$SCRIPTS_DIR/check-merge-commits" \
    "$SCRIPTS_DIR/check-merge-conflicts" \
    "$SCRIPTS_DIR/check-secrets"

# ── Register globally with git ────────────────────────────────────────────────
git config --global core.hooksPath "$HOOKS_DIR"

# ── Helper ────────────────────────────────────────────────────────────────────
has() { command -v "$1" > /dev/null 2>&1; }

tick() { printf "  \033[32m✓\033[0m  %-38s %s\n" "$1" "$2"; }
cross() { printf "  \033[31m✗\033[0m  %-38s %s\n" "$1" "$2"; }
skip() { printf "  \033[33m–\033[0m  %-38s %s\n" "$1" "$2"; }

echo ""
echo "Global pre-commit hooks installed."
echo "Hooks directory: $HOOKS_DIR"
echo ""
echo "Check status:"
echo "  ✓ active   ✗ tool not installed (skipped)   – conditional on file type"
echo ""

# ── Always-on checks ──────────────────────────────────────────────────────────
echo "Always-on:"
tick  "No merge commits"           ""
tick  "No merge conflict markers"  ""
tick  "No case sensitivity conflicts" ""
tick  "No ignored files tracked"   ""

if has trufflehog; then
    tick  "Secret scanning (trufflehog)" "$(trufflehog --version 2>/dev/null | head -1)"
else
    cross "Secret scanning (trufflehog)" "not installed — see install instructions below"
fi

# ── Conditional checks ────────────────────────────────────────────────────────
echo ""
echo "Conditional (triggered by file type + tool availability):"

if has dotnet; then
    skip  ".NET build + test (*.cs/csproj/sln)"    "dotnet $(dotnet --version 2>/dev/null)"
else
    cross ".NET build + test (*.cs/csproj/sln)"    "dotnet not installed"
fi

if has npm; then
    skip  "NPM tests (*.ts/tsx/js/jsx)"             "npm $(npm --version 2>/dev/null)"
else
    cross "NPM tests (*.ts/tsx/js/jsx)"             "npm not installed"
fi

if has dotnet; then
    skip  "T-SQL lint — dotnet tsqllint (*.sql)"    "dotnet $(dotnet --version 2>/dev/null)"
else
    cross "T-SQL lint — dotnet tsqllint (*.sql)"    "dotnet not installed"
fi

if has sqlfluff; then
    skip  "SQL style — sqlfluff (*.sql)"            "$(sqlfluff --version 2>/dev/null)"
else
    cross "SQL style — sqlfluff (*.sql)"            "not installed"
fi

if has cfn-lint; then
    skip  "CloudFormation — cfn-lint"               "$(cfn-lint --version 2>/dev/null)"
else
    cross "CloudFormation — cfn-lint"               "not installed"
fi

if [ -f "$REPO_DIR/.husky/pre-commit" ]; then
    skip  "Husky pre-commit"                        "found .husky/pre-commit"
else
    skip  "Husky pre-commit"                        "delegated if .husky/pre-commit present"
fi

if has pre-commit; then
    skip  "pre-commit framework"                    "$(pre-commit --version 2>/dev/null)"
else
    skip  "pre-commit framework"                    "delegated if .pre-commit-config.yaml present"
fi

# ── Optional tool install hints ───────────────────────────────────────────────
MISSING=""
has trufflehog || MISSING="$MISSING trufflehog"
has sqlfluff   || MISSING="$MISSING sqlfluff"
has cfn-lint   || MISSING="$MISSING cfn-lint"

if [ -n "$MISSING" ]; then
    echo ""
    echo "To install missing tools:"
    has trufflehog || echo "  trufflehog:  curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin"
    has sqlfluff   || echo "  sqlfluff:    pip install sqlfluff"
    has cfn-lint   || echo "  cfn-lint:    pip install cfn-lint"
fi

echo ""
