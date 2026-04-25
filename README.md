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
3. Print a status table of every check showing which are active and which need an optional tool installed

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

| Check | Script | What it catches |
|---|---|---|
| No merge commits | `scripts/check-merge-commits` | Blocks if `MERGE_HEAD` is present — rebase instead of merge |
| No merge conflict markers | `scripts/check-merge-conflicts` | Scans staged files for `<<<<<<<` / `>>>>>>>` |
| No case sensitivity conflicts | `scripts/check-case-sensitivity` | Fails if two tracked files differ only by case |
| No ignored files tracked | `scripts/check-ignored-files` | Fails if a tracked file is matched by `.gitignore` rules |
| Secret scanning | `scripts/check-secrets` | Runs `trufflehog --only-verified`; **skipped if not installed** |

### Conditional (triggered by staged file types + tool availability)

| Trigger | Check | Command |
|---|---|---|
| `.husky/pre-commit` exists | Delegate to husky | `sh .husky/pre-commit` |
| `.pre-commit-config.yaml` exists + `pre-commit` on PATH | Delegate to pre-commit framework | `pre-commit run` |
| `*.cs / *.csproj / *.sln / *.slnx / *.props / *.targets` + `dotnet` on PATH | Full .NET build + test | `scripts/buildtest` |
| `*.ts / *.tsx / *.js / *.jsx` + `package.json` + `npm` on PATH | NPM tests | `npm run test:noe2e` (falls back to `npm test`) |
| `*.sql` + `dotnet` on PATH | T-SQL lint | `dotnet tsqllint .` |
| `*.sql` + `sqlfluff` on PATH | SQL style lint | `sqlfluff lint .` |
| `*.yaml / *.yml / *.json / *.template` containing `AWSTemplateFormatVersion` + `cfn-lint` on PATH | CloudFormation lint | `cfn-lint <changed files>` |

All triggered checks must pass. Missing tools are skipped silently.
The commit is blocked on the first failure.

---

## What is always blocked

`pre-push` unconditionally blocks all pushes regardless of repo or content.

---

## Installing optional tools

```sh
# trufflehog (secret scanning) — https://github.com/trufflesecurity/trufflehog
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
  | sh -s -- -b /usr/local/bin

# sqlfluff (SQL style linting)
pip install sqlfluff

# cfn-lint (AWS CloudFormation linting)
pip install cfn-lint
```

After installing any tool, re-run `sh install.sh` to see the updated status table.

---

## Scripts

| Script | Source |
|---|---|
| `scripts/buildtest` | Vendored from [credfeto/scripts — buildtest](https://github.com/credfeto/scripts/blob/main/development/buildtest) |
| `scripts/buildcheck` | Vendored from [credfeto/scripts — buildcheck](https://github.com/credfeto/scripts/blob/main/development/buildcheck) |
| `scripts/check-case-sensitivity` | Port of [check-no-case-sensitivity-conflicts](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-case-sensitivity-conflicts/action.yml) |
| `scripts/check-ignored-files` | Port of [check-no-ignored-files](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-ignored-files/action.yml) |
| `scripts/check-merge-commits` | Port of [check-no-merge-commits](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-commits/action.yml) |
| `scripts/check-merge-conflicts` | Port of [check-no-merge-conflicts](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-conflicts/action.yml) |

---

## Two-layer enforcement

| Layer | Mechanism | Blocks |
|---|---|---|
| [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy) | HTTP 403 on git Data API / git-receive-pack / GraphQL git mutations | Programmatic commits via REST or GraphQL |
| These hooks (`core.hooksPath`) | exit 1 on pre-commit / pre-push | Local `git commit` and `git push` |
