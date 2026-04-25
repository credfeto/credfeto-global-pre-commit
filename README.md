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

## What runs on commit

The `pre-commit` hook inspects staged files and runs the relevant checks:

| Trigger | Check | Command |
|---|---|---|
| `.husky/pre-commit` exists | Delegate to husky | `sh .husky/pre-commit` |
| `.pre-commit-config.yaml` exists + `pre-commit` installed | Delegate to pre-commit framework | `pre-commit run` |
| `*.cs / *.csproj / *.sln / *.slnx / *.props / *.targets` staged + `dotnet` installed | Full .NET build + test | `scripts/buildtest` |
| `*.ts / *.tsx / *.js / *.jsx` staged + `package.json` exists + `npm` installed | NPM tests | `npm run test:noe2e` (falls back to `npm test`) |
| `*.sql` staged + `dotnet` installed | T-SQL lint | `dotnet tsqllint .` |
| `*.sql` staged + `sqlfluff` installed | SQL style lint | `sqlfluff lint .` |
| `*.yaml / *.yml / *.json / *.template` staged containing `AWSTemplateFormatVersion` + `cfn-lint` installed | CloudFormation lint | `cfn-lint <changed templates>` |

Checks are skipped silently if the required tool is not installed. All
triggered checks must pass — the commit is blocked on the first failure.

## What is always blocked

`pre-push` unconditionally blocks all pushes regardless of repo content.

## Scripts

`scripts/buildtest` and `scripts/buildcheck` are vendored from
[credfeto/scripts](https://github.com/credfeto/scripts/tree/main/development).
They run a full `dotnet restore → clean → build (--warnaserror) → test → pack`
cycle against the solution in the repo.

## Two-layer enforcement

| Layer | Mechanism | Blocks |
|---|---|---|
| [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy) | HTTP 403 on git Data API / git-receive-pack / GraphQL git mutations | Programmatic commits via REST or GraphQL |
| These hooks (`core.hooksPath`) | exit 1 on pre-commit / pre-push | Local `git commit` and `git push` |
