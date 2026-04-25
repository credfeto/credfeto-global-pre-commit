# credfeto-global-pre-commit

Global git hooks that run automatically on every `git commit` across every
repository on the machine — no per-repo setup required.

Used as the local enforcement layer alongside the
[GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy), which
blocks the same operations at the API level.

---

## How global hooks work

Git supports a machine-wide hooks directory via `core.hooksPath` (git ≥ 2.9).
When set, git uses that directory for every repository instead of the
per-repo `.git/hooks/`. The `install.sh` script sets this once and it applies
to all present and future clones.

---

## Install

```sh
git clone https://github.com/credfeto/credfeto-global-pre-commit.git ~/.global-hooks
cd ~/.global-hooks
sh install.sh
```

`install.sh` will:
1. Make all hook and script files executable
2. Run `git config --global core.hooksPath <hooks-dir>`
3. Symlink the `run-eslint`, `run-stylelint`, and `run-psscriptanalyzer` wrapper scripts to `~/.local/bin`
4. Pre-warm pre-commit managed hook environments (requires `pre-commit` on PATH)
5. Print a status table of every check showing which are active and which need an optional tool installed

`pre-commit` must be installed for linting to run (`pip install pre-commit`).

Example output:

```
Global pre-commit hooks installed.
Hooks directory: /home/user/.global-hooks/hooks

Check status:
  ✓ active   ✗ tool not installed (skipped)   – conditional on file type

Always-on:
  ✓  No merge commits
  ✓  No merge conflict markers
  ✓  No case sensitivity conflicts
  ✓  No ignored files tracked
  ✗  Secret scanning (trufflehog)        not installed — see install instructions below

Conditional (triggered by file type + tool availability):
  –  .NET build + test (*.cs/csproj/sln)  dotnet 10.0.203
  –  NPM tests (*.ts/tsx/js/jsx)          npm 10.9.7
  –  T-SQL lint — dotnet tsqllint (*.sql) dotnet 10.0.203
  ✗  SQL style — sqlfluff (*.sql)         not installed
  ✗  CloudFormation — cfn-lint            not installed
  –  Husky pre-commit                     delegated if .husky/pre-commit present
  –  pre-commit framework                 delegated if .pre-commit-config.yaml present

To install missing tools:
  trufflehog:  curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin
  sqlfluff:    pip install sqlfluff
  cfn-lint:    pip install cfn-lint
```

### Re-running after updates

```sh
cd ~/.global-hooks
git pull
sh install.sh
```

### Verify the install

```sh
git config --global core.hooksPath
# should print the hooks directory path
```

---

## Checks

### Always-on (every commit)

**Shell (run directly, before pre-commit):**

| Check | Script | What it catches |
|---|---|---|
| No merge commits | `scripts/check-merge-commits` | Blocks if `MERGE_HEAD` is present — rebase instead of merge |
| No ignored files tracked | `scripts/check-ignored-files` | Fails if a tracked file is matched by `.gitignore` rules |
| Secret scanning | `scripts/check-secrets` | Runs `trufflehog --only-verified`; **skipped if not installed** |

**Native pre-commit hooks (via `pre-commit/pre-commit-hooks`):**

| Check | Hook ID | What it catches |
|---|---|---|
| No merge conflict markers | `check-merge-conflict` | Scans staged files for `<<<<<<<` / `>>>>>>>` |
| No case sensitivity conflicts | `check-case-conflict` | Fails if two tracked files differ only by case |
| No large files | `check-added-large-files` | Blocks accidentally staged binaries/large assets |
| End-of-file newline | `end-of-file-fixer` | Ensures files end with a newline (auto-fixes) |
| No trailing whitespace | `trailing-whitespace` | Trims trailing whitespace (auto-fixes) |
| Consistent line endings | `mixed-line-ending` | Prevents CRLF/LF mix |
| Valid TOML | `check-toml` | Syntax-checks `*.toml` (`Cargo.toml`, `pyproject.toml`, etc.) |
| No private keys | `detect-private-key` | Pattern-matches common private key headers |
| Executables have shebangs | `check-executables-have-shebangs` | Catches executable files missing `#!` |
| Shebang scripts are `+x` | `check-shebang-scripts-are-executable` | Inverse — shebang files that aren't executable |

### Conditional (triggered by staged file types + tool availability)

| Trigger | Check | Command |
|---|---|---|
| `.husky/pre-commit` exists | Delegate to husky | `sh .husky/pre-commit` |
| `pre-commit` on PATH, repo has `.pre-commit-config.yaml` | Run project pre-commit hooks | `pre-commit run` |
| `pre-commit` on PATH, no project config | Run global linters (`.pre-commit-config.yaml`) | `pre-commit run --config <global>` |
| `*.cs / *.csproj / *.sln / *.slnx / *.props / *.targets` + `dotnet` on PATH | Full .NET build + test | `scripts/buildtest` |
| `*.ts / *.tsx / *.js / *.jsx` + `package.json` + `npm` on PATH | NPM tests | `npm run test:noe2e` (falls back to `npm test`) |
| `*.sql` + `dotnet` on PATH | T-SQL lint | `dotnet tsqllint .` |
| `*.sql` + `sqlfluff` on PATH | SQL style lint | `sqlfluff lint .` |
| `*.yaml / *.yml / *.json / *.template` containing `AWSTemplateFormatVersion` + `cfn-lint` on PATH | CloudFormation lint | `cfn-lint <changed files>` |

All triggered checks must pass. Missing tools are skipped silently.
The commit is blocked on the first failure.

### Super-linter equivalent (`.pre-commit-config.yaml`)

Mirrors the super-linter `VALIDATE_*` configuration, run by `pre-commit` against
staged files only (equivalent to `VALIDATE_ALL_CODEBASE: false`).

**Managed** — pre-commit downloads and caches the tool automatically; no system install required:

| VALIDATE_* | Tool | Hook repo |
|---|---|---|
| `VALIDATE_JSON` / `VALIDATE_XML` / `VALIDATE_YAML` (syntax) | pre-commit-hooks | `pre-commit/pre-commit-hooks` |
| `VALIDATE_BASH` | shellcheck | `shellcheck-py/shellcheck-py` |
| `VALIDATE_YAML` (style) | yamllint | `adrienverge/yamllint` |
| `VALIDATE_PYTHON` | flake8 | `PyCQA/flake8` |
| `VALIDATE_MD` | markdownlint | `igorshubovych/markdownlint-cli` |
| `VALIDATE_ANSIBLE` | ansible-lint | `ansible/ansible-lint` |

**System** — tool must be on PATH:

| VALIDATE_* | Tool | File trigger |
|---|---|---|
| `VALIDATE_DOCKERFILE` + `VALIDATE_DOCKERFILE_HADOLINT` | `hadolint` | `Dockerfile*` |
| `VALIDATE_GITHUB_ACTIONS` | `actionlint` | `.github/workflows/*.yml` |
| `VALIDATE_PYTHON_PYLINT` | `pylint` | `*.py` |
| `VALIDATE_CSS` | `stylelint` (via `run-stylelint`) | `*.css` (skips if no `package.json`) |
| `VALIDATE_ENV` | `dotenv-linter` | `.env` / `.env.*` |
| `VALIDATE_TYPESCRIPT_ES` | `eslint` (via `run-eslint`) | `*.ts/tsx/js/jsx` (skips if no eslint config) |
| `VALIDATE_XML` (full) | `xmllint` | `*.xml` |
| `VALIDATE_POWERSHELL` | `pwsh` + `PSScriptAnalyzer` (via `run-psscriptanalyzer`) | `*.ps1/psm1/psd1` |
| `VALIDATE_SQLFLUFF` | — | Handled by dedicated SQL check |
| `VALIDATE_CLOUDFORMATION` | — | Handled by dedicated CFN check |

---

## What is always blocked

`pre-push` unconditionally blocks all pushes regardless of repo or content.

---

## Installing optional tools

```sh
# pre-commit itself (required for linting to run)
pip install pre-commit

# Managed tools — pre-commit installs these automatically on first use.
# Nothing to install manually for:
#   shellcheck, yamllint, flake8, markdownlint, ansible-lint

# System tools — must be on PATH:

# Secret scanning
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
  | sh -s -- -b /usr/local/bin

# Docker / Actions linting
# hadolint: https://github.com/hadolint/hadolint/releases
# actionlint: https://github.com/rhysd/actionlint/releases

# CSS / TypeScript
npm install -g stylelint stylelint-config-standard
npm install -g eslint

# Python pylint
pip install pylint

# SQL / CloudFormation
pip install sqlfluff cfn-lint

# PowerShell
# pwsh: https://github.com/PowerShell/PowerShell/releases
# PSScriptAnalyzer: Install-Module -Name PSScriptAnalyzer -Force

# Env file linting
# dotenv-linter: https://github.com/dotenv-linter/dotenv-linter/releases

# XML (usually pre-installed)
apt install libxml2-utils               # xmllint (Debian/Ubuntu)
```

After installing any tool, re-run `sh install.sh` to see the updated status table.
Run `pre-commit autoupdate --config ~/.global-hooks/.pre-commit-config.yaml` to update managed hook versions.

---

## Scripts

| Script | Source |
|---|---|
| `scripts/buildtest` | Vendored from [credfeto/scripts — buildtest](https://github.com/credfeto/scripts/blob/main/development/buildtest) |
| `scripts/buildcheck` | Vendored from [credfeto/scripts — buildcheck](https://github.com/credfeto/scripts/blob/main/development/buildcheck) |
| `scripts/check-ignored-files` | Port of [check-no-ignored-files](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-ignored-files/action.yml) |
| `scripts/check-merge-commits` | Port of [check-no-merge-commits](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-commits/action.yml) |
| `scripts/run-eslint` | Wrapper for eslint — skips silently if no `package.json` or eslint config |
| `scripts/run-stylelint` | Wrapper for stylelint — skips silently if no `package.json` |
| `scripts/run-psscriptanalyzer` | Wrapper for PSScriptAnalyzer — runs per-file via pwsh |

---

## Two-layer enforcement

| Layer | Mechanism | Blocks |
|---|---|---|
| [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy) | HTTP 403 on git Data API / git-receive-pack / GraphQL git mutations | Programmatic commits via REST or GraphQL |
| These hooks (`core.hooksPath`) | exit 1 on pre-commit / pre-push | Local `git commit` and `git push` |
