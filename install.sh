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
    "$SCRIPTS_DIR/check-ignored-files" \
    "$SCRIPTS_DIR/check-merge-commits" \
    "$SCRIPTS_DIR/check-secrets" \
    "$SCRIPTS_DIR/run-eslint" \
    "$SCRIPTS_DIR/run-stylelint" \
    "$SCRIPTS_DIR/run-psscriptanalyzer"

# ── Register globally with git ────────────────────────────────────────────────
git config --global core.hooksPath "$HOOKS_DIR"

# ── Symlink system-hook wrappers onto PATH ────────────────────────────────────
# These are called by pre-commit's local system hooks.
mkdir -p "$HOME/.local/bin"
ln -sf "$SCRIPTS_DIR/run-eslint"           "$HOME/.local/bin/run-eslint"
ln -sf "$SCRIPTS_DIR/run-stylelint"        "$HOME/.local/bin/run-stylelint"
ln -sf "$SCRIPTS_DIR/run-psscriptanalyzer" "$HOME/.local/bin/run-psscriptanalyzer"

# ── Pre-warm pre-commit managed environments ──────────────────────────────────
if command -v pre-commit > /dev/null 2>&1; then
    echo "Pre-warming pre-commit hook environments (first run may be slow)..."
    pre-commit install-hooks --config "$REPO_DIR/.pre-commit-config.yaml" 2>&1 \
        | grep -v "^$" || true
fi

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
echo "Always-on (shell):"
tick  "No merge commits"           ""
tick  "No ignored files tracked"   ""

echo ""
echo "Always-on (pre-commit native hooks):"
tick  "No merge conflict markers"     "check-merge-conflict"
tick  "No case sensitivity conflicts" "check-case-conflict"
tick  "No large files added"          "check-added-large-files"
tick  "End-of-file newline"           "end-of-file-fixer (auto-fix)"
tick  "No trailing whitespace"        "trailing-whitespace (auto-fix)"
tick  "Consistent line endings"       "mixed-line-ending"
tick  "Valid TOML syntax"             "check-toml"
tick  "No private keys"               "detect-private-key"
tick  "Executables have shebangs"     "check-executables-have-shebangs"
tick  "Shebang scripts are +x"        "check-shebang-scripts-are-executable"

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
    skip  "pre-commit linters"                      "$(pre-commit --version 2>/dev/null)"
else
    cross "pre-commit linters"                      "pre-commit not installed — linting skipped"
fi

# ── Super-linter equivalent via pre-commit ────────────────────────────────────
echo ""
echo "Super-linter equivalent (run by pre-commit, staged files only):"
echo "  ✓ managed = pre-commit downloads the tool automatically"
echo "  – system  = tool must be on PATH"
echo ""

# Managed hooks (pre-commit installs these — no system install needed)
tick  "VALIDATE_JSON/XML/YAML syntax   (managed)" "pre-commit-hooks"
tick  "VALIDATE_BASH — shellcheck      (managed)" "shellcheck-py"
tick  "VALIDATE_YAML — yamllint        (managed)" "yamllint"
tick  "VALIDATE_PYTHON — flake8        (managed)" "flake8"
tick  "VALIDATE_MD — markdownlint      (managed)" "markdownlint-cli"
tick  "VALIDATE_ANSIBLE — ansible-lint (managed)" "ansible-lint"

# System hooks (tool must be on PATH)
if has hadolint; then
    skip  "VALIDATE_DOCKERFILE — hadolint   (system)" "$(hadolint --version 2>/dev/null)"
else
    cross "VALIDATE_DOCKERFILE — hadolint   (system)" "not installed"
fi

if has actionlint; then
    skip  "VALIDATE_GITHUB_ACTIONS — actionlint (system)" "$(actionlint --version 2>/dev/null)"
else
    cross "VALIDATE_GITHUB_ACTIONS — actionlint (system)" "not installed"
fi

if has pylint; then
    skip  "VALIDATE_PYTHON_PYLINT — pylint  (system)" "$(pylint --version 2>/dev/null | head -1)"
else
    cross "VALIDATE_PYTHON_PYLINT — pylint  (system)" "not installed"
fi

if has stylelint; then
    skip  "VALIDATE_CSS — stylelint          (system)" "$(stylelint --version 2>/dev/null)"
else
    cross "VALIDATE_CSS — stylelint          (system)" "not installed"
fi

if has dotenv-linter; then
    skip  "VALIDATE_ENV — dotenv-linter      (system)" "$(dotenv-linter --version 2>/dev/null)"
else
    cross "VALIDATE_ENV — dotenv-linter      (system)" "not installed"
fi

if has eslint; then
    skip  "VALIDATE_TYPESCRIPT_ES — eslint   (system)" "$(eslint --version 2>/dev/null)"
else
    cross "VALIDATE_TYPESCRIPT_ES — eslint   (system)" "not installed"
fi

if has xmllint; then
    skip  "VALIDATE_XML — xmllint            (system)" ""
else
    cross "VALIDATE_XML — xmllint            (system)" "not installed"
fi

if has pwsh; then
    skip  "VALIDATE_POWERSHELL — PSScriptAnalyzer (system)" "$(pwsh --version 2>/dev/null)"
else
    cross "VALIDATE_POWERSHELL — PSScriptAnalyzer (system)" "pwsh not installed"
fi

skip  "VALIDATE_SQLFLUFF — sqlfluff (*.sql)"  "handled by dedicated SQL check above"
skip  "VALIDATE_CLOUDFORMATION — cfn-lint"    "handled by dedicated CFN check above"

# ── Optional tool install hints ───────────────────────────────────────────────
MISSING_SYSTEM=""
has trufflehog    || MISSING_SYSTEM="$MISSING_SYSTEM trufflehog"
has sqlfluff      || MISSING_SYSTEM="$MISSING_SYSTEM sqlfluff"
has cfn-lint      || MISSING_SYSTEM="$MISSING_SYSTEM cfn-lint"
has hadolint      || MISSING_SYSTEM="$MISSING_SYSTEM hadolint"
has actionlint    || MISSING_SYSTEM="$MISSING_SYSTEM actionlint"
has pylint        || MISSING_SYSTEM="$MISSING_SYSTEM pylint"
has stylelint     || MISSING_SYSTEM="$MISSING_SYSTEM stylelint"
has dotenv-linter || MISSING_SYSTEM="$MISSING_SYSTEM dotenv-linter"
has eslint        || MISSING_SYSTEM="$MISSING_SYSTEM eslint"
has xmllint       || MISSING_SYSTEM="$MISSING_SYSTEM xmllint"
has pwsh          || MISSING_SYSTEM="$MISSING_SYSTEM pwsh"

if [ -n "$MISSING_SYSTEM" ]; then
    echo ""
    echo "To install missing system tools:"
    has trufflehog    || echo "  trufflehog:     curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin"
    has hadolint      || echo "  hadolint:       brew install hadolint  # or https://github.com/hadolint/hadolint/releases"
    has actionlint    || echo "  actionlint:     brew install actionlint  # or https://github.com/rhysd/actionlint/releases"
    has pylint        || echo "  pylint:         pip install pylint"
    has stylelint     || echo "  stylelint:      npm install -g stylelint stylelint-config-standard"
    has dotenv-linter || echo "  dotenv-linter:  https://github.com/dotenv-linter/dotenv-linter/releases"
    has eslint        || echo "  eslint:         npm install -g eslint"
    has sqlfluff      || echo "  sqlfluff:       pip install sqlfluff"
    has cfn-lint      || echo "  cfn-lint:       pip install cfn-lint"
    has xmllint       || echo "  xmllint:        apt install libxml2-utils  # or brew install libxml2"
    has pwsh          || echo "  pwsh:           https://github.com/PowerShell/PowerShell/releases"
fi

echo ""
