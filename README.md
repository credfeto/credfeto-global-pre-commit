# credfeto-global-pre-commit

Global git hooks that block all commits and pushes in restricted environments
(e.g. AI agent containers). Works as the local enforcement layer alongside the
[GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy), which
blocks the same operations at the API level.

## How it works

Git supports a global hooks directory via `core.hooksPath` (git 2.9+). When
set, every repo on the machine uses the hooks in that directory instead of
per-repo `.git/hooks/`. The hooks here unconditionally exit 1, so no commit
or push can complete regardless of which repo is being used.

## Install

```sh
git clone https://github.com/credfeto/credfeto-global-pre-commit.git
cd credfeto-global-pre-commit
sh install.sh
```

Or manually:

```sh
git config --global core.hooksPath /path/to/credfeto-global-pre-commit/hooks
chmod +x /path/to/credfeto-global-pre-commit/hooks/pre-commit
chmod +x /path/to/credfeto-global-pre-commit/hooks/pre-push
```

## Verify

```sh
git config --global core.hooksPath   # should print the hooks path
```

Any attempt to commit or push in any repo will now fail with:

```
error: commits are not permitted in this environment.
       Use pull requests via the GitHub API proxy instead.
```

## Hooks

| Hook | Blocks |
|---|---|
| `pre-commit` | `git commit` |
| `pre-push` | `git push` |

## Two-layer enforcement

| Layer | Mechanism | Blocks |
|---|---|---|
| API proxy | HTTP 403 on git Data API / git-receive-pack | Programmatic commits via API or GraphQL |
| These hooks | `core.hooksPath` exit 1 | Local `git commit` / `git push` |

Together they prevent code being written to any repository through any path.
