# credfeto-global-pre-commit

Global git hooks installed via `core.hooksPath`. Applies to every repo on the
machine without any per-repo setup. Used as the local enforcement layer
alongside the [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy).

## Install

```sh
git clone https://github.com/credfeto/credfeto-global-pre-commit.git
cd credfeto-global-pre-commit
sh install.sh
```

## Checks that run on every commit

These always run regardless of what files are staged:

| Check | Script | Notes |
|---|---|---|
| No merge commits | `scripts/check-merge-commits` | Blocks if `MERGE_HEAD` present — rebase instead |
| No merge conflict markers | `scripts/check-merge-conflicts` | Scans staged files for `<<<<<<<` / `>>>>>>>` |
| No case sensitivity conflicts | `scripts/check-case-sensitivity` | Fails if two tracked files differ only by case |
| No ignored files tracked | `scripts/check-ignored-files` | Fails if a tracked file matches `.gitignore` rules |
| Secret scanning | `scripts/check-secrets` | Runs `trufflehog` if on PATH; skipped silently if not installed |

## Checks that run when relevant tools/files are present

| Trigger | Check | Command |
|---|---|---|
| `.husky/pre-commit` exists | Delegate to husky | `sh .husky/pre-commit` |
| `.pre-commit-config.yaml` + `pre-commit` installed | Delegate to pre-commit framework | `pre-commit run` |
| `*.cs/csproj/sln/slnx/props/targets` staged + `dotnet` available | Full .NET build + test | `scripts/buildtest` |
| `*.ts/tsx/js/jsx` staged + `package.json` + `npm` available | NPM tests | `npm run test:noe2e` (falls back to `npm test`) |
| `*.sql` staged + `dotnet` available | T-SQL lint | `dotnet tsqllint .` |
| `*.sql` staged + `sqlfluff` available | SQL style lint | `sqlfluff lint .` |
| `*.yaml/yml/json/template` staged containing `AWSTemplateFormatVersion` + `cfn-lint` available | CloudFormation lint | `cfn-lint <files>` |

Checks that require a tool (trufflehog, sqlfluff, cfn-lint) are skipped
silently if the tool is not installed. All triggered checks must pass — the
commit is blocked on the first failure.

## Installing optional tools

```sh
# trufflehog (secret scanning)
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# sqlfluff
pip install sqlfluff

# cfn-lint
pip install cfn-lint
```

## What is always blocked

`pre-push` unconditionally blocks all pushes regardless of repo content.

## Scripts

| Script | Source |
|---|---|
| `scripts/buildtest` | Vendored from [credfeto/scripts](https://github.com/credfeto/scripts/blob/main/development/buildtest) |
| `scripts/buildcheck` | Vendored from [credfeto/scripts](https://github.com/credfeto/scripts/blob/main/development/buildcheck) |
| `scripts/check-case-sensitivity` | Equivalent of [funfair-server-template check-no-case-sensitivity-conflicts](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-case-sensitivity-conflicts/action.yml) |
| `scripts/check-ignored-files` | Equivalent of [funfair-server-template check-no-ignored-files](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-ignored-files/action.yml) |
| `scripts/check-merge-commits` | Equivalent of [funfair-server-template check-no-merge-commits](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-commits/action.yml) |
| `scripts/check-merge-conflicts` | Equivalent of [funfair-server-template check-no-merge-conflicts](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-conflicts/action.yml) |

## Two-layer enforcement

| Layer | Mechanism | Blocks |
|---|---|---|
| [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy) | HTTP 403 on git Data API / git-receive-pack / GraphQL git mutations | Programmatic commits via REST or GraphQL |
| These hooks (`core.hooksPath`) | exit 1 on pre-commit / pre-push | Local `git commit` and `git push` |
