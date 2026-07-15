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
per-repo `.git/hooks/`. The `install` script sets this once and it applies
to all present and future clones.

---

## Dependencies

Every hook uses `language: system` and calls a binary already on `PATH`.
Running `install` auto-detects the platform (Arch-based or Debian-based) and
calls the appropriate deps script automatically. You can also run them manually:

### Arch Linux

```sh
./install-deps-arch
```

Requires an AUR helper (`paru` or `yay`). The script will print instructions for
installing one if neither is found. If [Chaotic-AUR](https://aur.chaotic.cx/) is
configured, pre-compiled `-bin` packages are used automatically — no local
compilation required.

| Source | Packages |
| -------- | ---------- |
| `pacman` | `git`, `python-pre-commit`, `shellcheck`, `yamllint`, `python-flake8`, `python-pylint`, `ansible-lint`, `libxml2`, `trivy` |
| AUR | `hadolint-bin`, `dotenv-linter-bin`, `sqlfluff`, `python-cfn-lint` |
| GitHub releases | `actionlint`, `trufflehog` (downloaded to `/usr/local/bin`) |
| `pipx` | `pre-commit-hooks` (no AUR package exists) |
| `npm -g` | `markdownlint-cli`, `eslint`, `stylelint`, `stylelint-config-standard` |
| `dotnet tool` | `PowerShell` (`pwsh`) — skipped with a warning if `dotnet` is not on `PATH` |

Node.js is intentionally not installed by the script — use [nvm](https://github.com/nvm-sh/nvm)
to manage it. Similarly, the .NET SDK is not installed — install it separately
and the script will pick it up automatically.

### Debian / Ubuntu

Tested on Ubuntu 22.04 LTS and Debian 12 (Bookworm).

```sh
./install-deps-debian
```

| Source | Packages |
| -------- | ---------- |
| `apt` | `git`, `pre-commit`, `shellcheck`, `yamllint`, `python3-flake8`, `python3-pylint`, `libxml2-utils`, `curl`, `gpg`, `pipx` |
| `apt` (fallback: `pipx`) | `ansible-lint` — installed via `pipx` on older releases where the `apt` package is unavailable |
| GitHub releases | `hadolint`, `actionlint`, `dotenv-linter`, `trufflehog`, `trivy` (downloaded to `/usr/local/bin`) |
| `pipx` | `pre-commit-hooks`, `sqlfluff`, `cfn-lint` |
| `npm -g` | `markdownlint-cli`, `eslint`, `stylelint`, `stylelint-config-standard` |
| `dotnet tool` | `PowerShell` (`pwsh`) — skipped with a warning if `dotnet` is not on `PATH` |

If `go` is on `PATH`, `actionlint` is installed via `go install` instead of a
binary download. Node.js and the .NET SDK are not installed by the script — manage
them separately (nvm for Node.js).

### Notes applicable to both scripts

- Safe to run multiple times — each step is idempotent.
- `pwsh` is installed as a `dotnet` global tool (`dotnet tool install --global PowerShell`).
  Global tools land in `~/.dotnet/tools/` which must be on `PATH`:

  ```sh
  export PATH="$HOME/.dotnet/tools:$PATH"
  ```

- `pipx` installs console scripts into `~/.local/bin/` (XDG-compliant).
  Ensure `~/.local/bin` is on `PATH` (most modern distributions include it by default).

---

## Install

```sh
git clone https://github.com/credfeto/credfeto-global-pre-commit.git ~/.global-hooks
cd ~/.global-hooks
./install
```

`install` will:

1. Make all hook and script files executable
2. Auto-detect the platform and run `install-deps-arch` or `install-deps-debian`
3. Run `git config --global core.hooksPath <hooks-dir>`
4. Symlink the `run-eslint`, `run-stylelint`, and `run-psscriptanalyzer` wrapper scripts to `~/.local/bin`
5. Validate the `.pre-commit-config.yaml` schema (no managed environments to install — every hook is `language: system`)
6. Print a status table of every check showing which are active and which need a system tool installed

`pre-commit` must be installed for linting to run (`pip install pre-commit`).

### Why every hook is `language: system`

By default, pre-commit auto-installs each hook into its own managed environment
(a Python venv, a node_modules, etc.) on first run — typically 1–3 minutes
and ~150 MB on disk. That cost is a one-off on a developer workstation, but on
ephemeral containers (Docker / CI / agent spawns) it's paid on every fresh
spawn.

This config opts out of that model: every hook is declared `language: system`
and calls a binary already on `PATH`. Faster startup, smaller image, no
per-spawn redownloads — but you have to install the tools yourself. `install`
prints what's missing and exact install commands.

System tools required for full coverage: `pre-commit-hooks` (pip), `shellcheck`,
`yamllint`, `flake8`, `markdownlint`, `ansible-lint`, `hadolint`, `actionlint`,
`pylint`, `stylelint`, `dotenv-linter`, `eslint`, `xmllint`, `pwsh`,
`trufflehog`, `trivy`, `sqlfluff`, `cfn-lint`. Anything missing → that hook is
silently skipped (with a warning at install time).

Example output:

```text
Global pre-commit hooks installed.
Hooks directory: /home/user/.global-hooks/src/hooks

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
./install
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
| --- | --- | --- |
| No merge commits | `scripts/check-merge-commits` | Blocks if `MERGE_HEAD` is present — rebase instead of merge |
| No ignored files tracked | `scripts/check-ignored-files` | Fails if a tracked file is matched by `.gitignore` rules |
| Secret scanning | `scripts/check-secrets` | Runs `trufflehog --only-verified`; **skipped if not installed** |

**Native pre-commit hooks (via `pre-commit/pre-commit-hooks`):**

| Check | Hook ID | What it catches |
| --- | --- | --- |
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
| --- | --- | --- |
| `pre-commit` on PATH, repo has `.pre-commit-config.yaml` | Run project pre-commit hooks | `pre-commit run` |
| `pre-commit` on PATH, no project config | Run global linters (`.pre-commit-config.yaml`) | `pre-commit run --config <global>` |
| `*.cs / *.csproj / *.sln / *.slnx / *.props / *.targets` + `dotnet` on PATH | Full .NET build + test (integration tests and all benchmark test projects always excluded from the main run via a static filter; only the benchmark projects staged changes could affect are then run individually and sequentially, see `scripts/benchmark-test-affected`) | `scripts/buildtest` |
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
| --- | --- | --- |
| `VALIDATE_JSON` / `VALIDATE_XML` / `VALIDATE_YAML` (syntax) | pre-commit-hooks | `pre-commit/pre-commit-hooks` |
| `VALIDATE_BASH` | shellcheck | `shellcheck-py/shellcheck-py` |
| `VALIDATE_YAML` (style) | yamllint | `adrienverge/yamllint` |
| `VALIDATE_PYTHON` | flake8 | `PyCQA/flake8` |
| `VALIDATE_MD` | markdownlint | `igorshubovych/markdownlint-cli` |
| `VALIDATE_ANSIBLE` | ansible-lint | `ansible/ansible-lint` |

**System** — tool must be on PATH:

| VALIDATE_* | Tool | File trigger |
| --- | --- | --- |
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

**Additional security checks** — not part of the Super-linter `VALIDATE_*` set, added independently; tool must be on PATH:

| Check | Tool | File trigger |
| --- | --- | --- |
| Dependency vulnerabilities | `trivy fs --scanners vuln` | `package-lock.json`, `packages.lock.json`, `go.sum`, `requirements*.txt`, `Gemfile.lock`, `poetry.lock`, `Pipfile.lock` |

`trivy`'s secret scanner is deliberately not enabled — it would duplicate the
verified-only `trufflehog` check above with noisier, unverified findings.

---

## Baseline mode (`--all-files`)

Run the full check suite against the whole tracked tree — independent of
whatever is (or isn't) staged — with:

```sh
sh ~/.global-hooks/src/hooks/pre-commit --all-files
```

This is the supported way to get an "everything in the repo" signal, e.g. as
a pre-work baseline check before starting a task. Compared to the default
(no-argument) invocation:

| | Default (`pre-commit`) | `--all-files` |
| --- | --- | --- |
| File list checks run against | Staged files (`git diff --cached`) | Every tracked file (`git ls-files`) |
| Empty stage | Aborts (`nothing is staged`) | Runs normally |
| Branch guard (`main`/`master`) | Blocks | Skipped |
| Git identity/GPG check | Runs | Skipped |
| Merge-commit guard | Runs | Skipped |
| Ignored-file / dotnet-tools.json / install-location / freshness guards | Runs | Runs (unchanged) |
| `pre-commit run` | Staged files only | `--all-files` |
| Changelog / .NET / NPM / SQL / CloudFormation category checks | Gated on staged files | Gated on tracked files |

Auto-fixers (`sqlfluff fix`, the .NET formatter, `clean-package-lock-registry`)
still run and re-stage what they change, exactly as they do in the default
mode — `--all-files` runs the same checks, just against a wider file list.

The protected/linter-config-file guards (blocking staged changes to
`.shellcheckrc`, `.ai-instructions`, `ai/global/`, etc.) still key off
whatever is staged, in both modes — they guard commit *content*, not the
tracked tree, so they are unaffected by `--all-files`.

An unrecognised argument is rejected with a non-zero exit and an error
message; the default no-argument invocation is unaffected by this mode.

---

## What is always blocked

`pre-push` unconditionally blocks all pushes regardless of repo or content.

---

## Installing optional tools

Use the provided dependency scripts — see [Dependencies](#dependencies) above.
They handle all system tools, install them idempotently, and are safe to re-run
after updates.

After installing any tool, re-run `./install` to see the updated status table.
Run `pre-commit autoupdate --config ~/.global-hooks/src/.pre-commit-config.yaml` to update managed hook versions.

---

## Scripts

| Script | Source |
| --- | --- |
| `scripts/buildtest` | Vendored from [credfeto/scripts — buildtest](https://github.com/credfeto/scripts/blob/main/development/buildtest) |
| `scripts/benchmark-test-affected` | Local addition, decides which benchmark test projects `buildtest`'s separate benchmark-only test step should run, from staged git changes alone (no `dotnet` required) |
| `scripts/latest-target-framework` | Local addition, prints a multi-targeted `.csproj`'s latest target framework moniker so `buildtest`'s benchmark test step can restrict itself to it (older frameworks are assumed to work); prints nothing for a single-targeted project (no `dotnet` required) |
| `scripts/buildcheck` | Vendored from [credfeto/scripts — buildcheck](https://github.com/credfeto/scripts/blob/main/development/buildcheck) |
| `scripts/check-ignored-files` | Port of [check-no-ignored-files](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-ignored-files/action.yml) |
| `scripts/check-merge-commits` | Port of [check-no-merge-commits](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-commits/action.yml) |
| `scripts/run-eslint` | Wrapper for eslint — skips silently if no `package.json` or eslint config |
| `scripts/run-stylelint` | Wrapper for stylelint — skips silently if no `package.json` |
| `scripts/run-psscriptanalyzer` | Wrapper for PSScriptAnalyzer — runs per-file via pwsh |

---

## Two-layer enforcement

| Layer | Mechanism | Blocks |
| --- | --- | --- |
| [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy) | HTTP 403 on git Data API / git-receive-pack / GraphQL git mutations | Programmatic commits via REST or GraphQL |
| These hooks (`core.hooksPath`) | exit 1 on pre-commit / pre-push | Local `git commit` and `git push` |
