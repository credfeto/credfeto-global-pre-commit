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
    "$SCRIPTS_DIR/check-secrets" \
    "$SCRIPTS_DIR/check-linters"

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

# ── Super-linter equivalent (check-linters) ───────────────────────────────────
echo ""
echo "Super-linter equivalent (staged files only, tool must be on PATH):"

if has shellcheck; then
    skip  "VALIDATE_BASH — shellcheck (*.sh/shebang)"     "$(shellcheck --version 2>/dev/null | grep version: | awk '{print $2}')"
else
    cross "VALIDATE_BASH — shellcheck (*.sh/shebang)"     "not installed"
fi

if has ansible-lint; then
    skip  "VALIDATE_ANSIBLE — ansible-lint (*.yml/yaml)"  "$(ansible-lint --version 2>/dev/null | head -1)"
else
    cross "VALIDATE_ANSIBLE — ansible-lint (*.yml/yaml)"  "not installed"
fi

if has stylelint; then
    skip  "VALIDATE_CSS — stylelint (*.css)"              "$(stylelint --version 2>/dev/null)"
else
    cross "VALIDATE_CSS — stylelint (*.css)"              "not installed"
fi

if has dotenv-linter; then
    skip  "VALIDATE_ENV — dotenv-linter (.env.*)"         "$(dotenv-linter --version 2>/dev/null)"
else
    cross "VALIDATE_ENV — dotenv-linter (.env.*)"         "not installed"
fi

if has hadolint; then
    skip  "VALIDATE_DOCKERFILE — hadolint (Dockerfile*)"  "$(hadolint --version 2>/dev/null)"
else
    cross "VALIDATE_DOCKERFILE — hadolint (Dockerfile*)"  "not installed"
fi

if has actionlint; then
    skip  "VALIDATE_GITHUB_ACTIONS — actionlint (.github/workflows/*.yml)" "$(actionlint --version 2>/dev/null)"
else
    cross "VALIDATE_GITHUB_ACTIONS — actionlint (.github/workflows/*.yml)" "not installed"
fi

if has jq; then
    skip  "VALIDATE_JSON — jq (*.json)"                   "$(jq --version 2>/dev/null)"
else
    cross "VALIDATE_JSON — jq (*.json)"                   "not installed"
fi

if has markdownlint; then
    skip  "VALIDATE_MD — markdownlint (*.md)"             "$(markdownlint --version 2>/dev/null)"
else
    cross "VALIDATE_MD — markdownlint (*.md)"             "not installed"
fi

if has pwsh; then
    skip  "VALIDATE_POWERSHELL — PSScriptAnalyzer (*.ps1)" "$(pwsh --version 2>/dev/null)"
else
    cross "VALIDATE_POWERSHELL — PSScriptAnalyzer (*.ps1)" "pwsh not installed"
fi

if has flake8; then
    skip  "VALIDATE_PYTHON — flake8 (*.py)"               "$(flake8 --version 2>/dev/null | head -1)"
else
    cross "VALIDATE_PYTHON — flake8 (*.py)"               "not installed"
fi

if has pylint; then
    skip  "VALIDATE_PYTHON_PYLINT — pylint (*.py)"        "$(pylint --version 2>/dev/null | head -1)"
else
    cross "VALIDATE_PYTHON_PYLINT — pylint (*.py)"        "not installed"
fi

if has eslint || [ -f "$REPO_DIR/node_modules/.bin/eslint" ]; then
    skip  "VALIDATE_TYPESCRIPT_ES — eslint (*.ts/tsx)"    ""
else
    cross "VALIDATE_TYPESCRIPT_ES — eslint (*.ts/tsx)"    "not installed"
fi

if has xmllint; then
    skip  "VALIDATE_XML — xmllint (*.xml)"                ""
else
    cross "VALIDATE_XML — xmllint (*.xml)"                "not installed"
fi

if has yamllint; then
    skip  "VALIDATE_YAML — yamllint (*.yml/yaml)"         "$(yamllint --version 2>/dev/null)"
else
    cross "VALIDATE_YAML — yamllint (*.yml/yaml)"         "not installed"
fi

skip  "VALIDATE_SQLFLUFF — sqlfluff (*.sql)"              "handled by dedicated SQL check above"
skip  "VALIDATE_CLOUDFORMATION — cfn-lint"                "handled by dedicated CFN check above"

# ── Optional tool install hints ───────────────────────────────────────────────
MISSING=""
has trufflehog   || MISSING="$MISSING trufflehog"
has sqlfluff     || MISSING="$MISSING sqlfluff"
has cfn-lint     || MISSING="$MISSING cfn-lint"
has shellcheck   || MISSING="$MISSING shellcheck"
has hadolint     || MISSING="$MISSING hadolint"
has actionlint   || MISSING="$MISSING actionlint"
has markdownlint || MISSING="$MISSING markdownlint"
has yamllint     || MISSING="$MISSING yamllint"
has stylelint    || MISSING="$MISSING stylelint"
has dotenv-linter || MISSING="$MISSING dotenv-linter"
has ansible-lint || MISSING="$MISSING ansible-lint"
has flake8       || MISSING="$MISSING flake8"
has pylint       || MISSING="$MISSING pylint"
has pwsh         || MISSING="$MISSING pwsh"
has jq           || MISSING="$MISSING jq"
has xmllint      || MISSING="$MISSING xmllint"

if [ -n "$MISSING" ]; then
    echo ""
    echo "To install missing tools:"
    has trufflehog    || echo "  trufflehog:     curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin"
    has shellcheck    || echo "  shellcheck:     apt install shellcheck  # or brew install shellcheck"
    has hadolint      || echo "  hadolint:       brew install hadolint  # or https://github.com/hadolint/hadolint/releases"
    has actionlint    || echo "  actionlint:     brew install actionlint  # or https://github.com/rhysd/actionlint/releases"
    has markdownlint  || echo "  markdownlint:   npm install -g markdownlint-cli"
    has yamllint      || echo "  yamllint:       pip install yamllint"
    has stylelint     || echo "  stylelint:      npm install -g stylelint stylelint-config-standard"
    has dotenv-linter || echo "  dotenv-linter:  https://github.com/dotenv-linter/dotenv-linter/releases"
    has ansible-lint  || echo "  ansible-lint:   pip install ansible-lint"
    has flake8        || echo "  flake8:         pip install flake8"
    has pylint        || echo "  pylint:         pip install pylint"
    has pwsh          || echo "  pwsh:           https://github.com/PowerShell/PowerShell/releases"
    has sqlfluff      || echo "  sqlfluff:       pip install sqlfluff"
    has cfn-lint      || echo "  cfn-lint:       pip install cfn-lint"
    has jq            || echo "  jq:             apt install jq  # or brew install jq"
    has xmllint       || echo "  xmllint:        apt install libxml2-utils  # or brew install libxml2"
fi

echo ""
