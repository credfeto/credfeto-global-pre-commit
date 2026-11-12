# credfeto-global-pre-commit

Global git hooks that run automatically on every `git commit` across every
repository on the machine, with no per-repo setup required.

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

Expects [Chaotic-AUR](https://aur.chaotic.cx/) to be configured as a `pacman`
repo, because some of the packages below are only available from it. No AUR
helper is needed and nothing is built with `makepkg`.

| Source | Packages |
| -------- | ---------- |
| `pacman` | `git`, `bats`, `go`, `pre-commit`, `shellcheck`, `yamllint`, `python-flake8`, `python-pylint`, `ansible-lint`, `libxml2`, `python-pipx`, `trivy`, `parallel`, `curl`, `nvm`, `nodejs`, `npm`, `sqlfluff`, `python-cfn-lint` |
| GitHub releases | `hadolint`, `actionlint`, `dotenv-linter`, `trufflehog` (downloaded to `/usr/local/bin`) |
| `pipx` (shared, see below) | `pre-commit-hooks` (no AUR package exists) |
| `npm -g` (shared, see below) | `markdownlint-cli`, `eslint`, `stylelint`, `stylelint-config-standard` |
| `dotnet tool` | `PowerShell` (`pwsh`), `Credfeto.DotNet.Repo.Formatter` (`cscleanup`), skipped with a warning if `dotnet` is not on `PATH` |
| `go install` | `composite-action-lint` |

The `pacman` `nvm` package does not load nvm into the shell. The hook linters do not
need it, because they run on the shared `pacman` `nodejs`, but before `nvm` (and any
Node.js it installs) can be used for your own projects, source its init script from
your shell rc file (e.g. `~/.bashrc`) and open a new shell:

```sh
source /usr/share/nvm/init-nvm.sh
```

### Debian / Ubuntu

Tested on Ubuntu 22.04 LTS and Debian 12 (Bookworm).

```sh
./install-deps-debian
```

| Source | Packages |
| -------- | ---------- |
| `apt` | `git`, `bats`, `pre-commit`, `shellcheck`, `yamllint`, `python3-flake8`, `python3-venv`, `libxml2-utils`, `curl`, `gpg`, `pipx`, `parallel`, `xz-utils` |
| `apt` (fallback: shared `pipx`) | `ansible-lint`, `python3-pylint` (`pylint` from `pipx`), installed via `pipx` on releases where the `apt` package is unavailable |
| GitHub releases | `hadolint`, `actionlint`, `dotenv-linter`, `trufflehog`, `trivy` (downloaded to `/usr/local/bin`) |
| nodejs.org | Node.js (`node`, `npm`), the latest LTS tarball, checksum-verified and unpacked into `/usr/local` |
| `pipx` (shared, see below) | `pre-commit-hooks`, `sqlfluff`, `cfn-lint` |
| `npm -g` (shared, see below) | `markdownlint-cli`, `eslint`, `stylelint`, `stylelint-config-standard` |
| `dotnet tool` | `PowerShell` (`pwsh`), `Credfeto.DotNet.Repo.Formatter` (`cscleanup`), skipped with a warning if `dotnet` is not on `PATH` |
| `go install` | `composite-action-lint`, skipped with a warning if `go` is not on `PATH` |

If `go` is on `PATH`, `actionlint` is installed via `go install` instead of a
binary download.

`nvm` is not in `apt`, so it is installed using nvm's official install script.
The `apt` `nodejs` is older than the npm linters support, so Node.js is installed from
nodejs.org instead; it is skipped only when `/usr/local/bin/node` is already the latest
LTS and a real file, not a link (e.g. into an nvm Node under `$HOME`).

### Notes applicable to both scripts

- Safe to run multiple times: each step is idempotent.
- The .NET SDK is not installed: install it separately and the script will pick it up
  automatically.
- `pwsh` and `cscleanup` are installed as local `dotnet` tools in the `$HOME`-scoped
  tool manifest (`~/.config/dotnet-tools.json` or `~/dotnet-tools.json`, whichever the
  SDK uses; one is created if neither exists), with the `PSScriptAnalyzer` module
  alongside `pwsh`. They run as `dotnet pwsh` and `dotnet cscleanup` from any directory
  under `$HOME` and need no `PATH` change.
- `pipx` packages are installed once for every account, not per user: as root, with
  `PIPX_HOME=/opt/pipx`, `PIPX_BIN_DIR=/usr/local/bin` and
  `PIPX_MAN_DIR=/usr/local/share/man`, under `umask 022`, after which `/opt/pipx` is
  made readable by all users (`chmod -R a+rX`). This is what lets `./install --system`
  hooks run the `pre-commit-hooks` tools (`check-merge-conflict`, `end-of-file-fixer`,
  ...) for every user. A copy already in your own `~/.local/bin` is left alone and does
  not stop the shared install; re-running the script repairs a shared install that other
  users cannot read. To install one package by hand the same way:

  ```sh
  (umask 022 && sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install pre-commit-hooks) && sudo chmod -R a+rX /opt/pipx
  ```

- `npm -g` packages are also installed once for every account, never into an nvm Node
  under `$HOME`: as root, with `--prefix /usr/local`, under `umask 022`, after which
  `/usr/local/lib/node_modules` is made readable by all users (`chmod -R a+rX`). Their
  commands land in `/usr/local/bin` and run on the shared `node` (from `pacman` on Arch,
  from nodejs.org in `/usr/local` on Debian / Ubuntu). `--engine-strict` makes a `node`
  too old for a package fail the install, and `--ignore-scripts` stops package scripts
  running as root. Copies already in your own nvm Node are left alone and do not stop
  the shared install. To install one package by hand the same way:

  ```sh
  (umask 022 && sudo npm install --global --prefix /usr/local --engine-strict --ignore-scripts eslint) && sudo chmod -R a+rX /usr/local/lib/node_modules
  ```

---

## Install

```sh
git clone https://github.com/credfeto/credfeto-global-pre-commit.git ~/.global-hooks
cd ~/.global-hooks
./install
```

To install for every user on the machine instead, run `./install --system` (needs `sudo`).

`install` will:

1. Make all hook and script files executable, changing only files that are not executable already, so it also works from a read-only, root-owned copy
2. Auto-detect the platform and run `install-deps-arch` or `install-deps-debian`
3. Run `git config --global core.hooksPath <hooks-dir>` (`git config --system` with `--system`)
4. Symlink the `run-eslint`, `run-stylelint`, `run-psscriptanalyzer`, `run-bats`, and `run-pylint` wrapper scripts to `~/.local/bin` (not required for the hook, which puts `src/scripts` on `PATH` itself), and symlink `composite-action-lint` there too if it is built in the Go bin directory (`$(go env GOPATH)/bin`)
   - With `--system`: no `run-*` links are created, and `composite-action-lint` is copied into `/usr/local/bin` with mode `0755` rather than linked, so every user can run it
5. Validate the `.pre-commit-config.yaml` schema (no managed environments to install, because every hook is `language: system`)
6. Print a status table of every check showing which are active and which need a system tool installed
   - With `--system`: a `pipx` tool (`pre-commit-hooks`, `sqlfluff`, `cfn-lint`, `pylint`, `ansible-lint`) found only under `$HOME`, or whose shared `/opt/pipx` venv other users cannot read, is marked as failing, because other users cannot run it
   - With `--system`: an npm tool (`markdownlint`, `eslint`, `stylelint`) found only under `$HOME`, whose shared `/usr/local/lib/node_modules` package other users cannot read, or whose `node` is only under `$HOME` or not executable by other users, is marked as failing for the same reason

`pre-commit` must be installed for linting to run (`pip install pre-commit`).

### Why every hook is `language: system`

By default, pre-commit auto-installs each hook into its own managed environment
(a Python venv, a node_modules, etc.) on first run, typically 1–3 minutes
and ~150 MB on disk. That cost is a one-off on a developer workstation, but on
ephemeral containers (Docker / CI / agent spawns) it's paid on every fresh
spawn.

This config opts out of that model: every hook is declared `language: system`
and calls a binary already on `PATH`. Faster startup, smaller image, no
per-spawn redownloads, but you have to install the tools yourself. `install`
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
  sqlfluff:    (umask 022 && sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install sqlfluff) && sudo chmod -R a+rX /opt/pipx
  cfn-lint:    (umask 022 && sudo env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_MAN_DIR=/usr/local/share/man pipx install cfn-lint) && sudo chmod -R a+rX /opt/pipx
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
| No merge commits | `scripts/check-merge-commits` | Blocks if `MERGE_HEAD` is present (rebase instead of merge) |
| No ignored files tracked | `scripts/check-ignored-files` | Fails if a tracked file is matched by `.gitignore` rules |
| No `src/FunFair.props` outside funfair-tech | `scripts/check-funfair-props` | When the `origin` remote's owner is not `funfair-tech` (case-insensitive; skipped when there is no `origin`), `git rm`s a tracked `src/FunFair.props` (staging the removal) or deletes an untracked one, then fails so the commit can be re-run with the removal included. Under `git commit -a`, `-i` or `<paths>`, git discards index changes made by a failing hook, so the file is only deleted and the message gives the `git rm` command to stage it. Also runs in `--all-files` mode |
| Secret scanning | `scripts/check-secrets` | Runs `trufflehog --only-verified`; **skipped if not installed** |

**pre-commit hooks (tools from the `pre-commit-hooks` pip package, run as `language: system`):**

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
| Shebang scripts are `+x` | `check-shebang-scripts-are-executable` | Inverse: shebang files that aren't executable |

### Conditional (triggered by staged file types + tool availability)

| Trigger | Check | Command |
| --- | --- | --- |
| `pre-commit` on PATH, repo has `.pre-commit-config.yaml` | Run project pre-commit hooks | `pre-commit run` |
| `pre-commit` on PATH, no project config | Run global linters (`.pre-commit-config.yaml`) | `pre-commit run --config <global>` |
| `*.cs / *.csproj / *.sln / *.slnx / *.props / *.targets / *.globalconfig / *.ruleset` | Benchmark project naming: a project whose `.cs` files use BenchmarkDotNet (`using BenchmarkDotNet…` or `[Benchmark]`, even when the package only comes in transitively) must be named `<Name>.Benchmark.Tests` and use that namespace, the only benchmark name `buildtest` keeps out of its main test run | `scripts/check-benchmark-project-names` |
| `*.cs / *.csproj / *.sln / *.slnx / *.props / *.targets` + `dotnet` on PATH | Full .NET build + test (integration tests and all benchmark test projects always excluded from the main run via a static filter; only the benchmark projects staged changes could affect are then run individually and sequentially, see `scripts/benchmark-test-affected`) | `scripts/buildtest` |
| `*.ts / *.tsx / *.js / *.jsx` + `package.json` + `npm` on PATH | NPM tests | `npm run test:noe2e` (falls back to `npm test`) |
| `*.sql` + `dotnet` on PATH | T-SQL lint | `dotnet tsqllint .` |
| `*.sql` + `sqlfluff` on PATH | SQL style fix of staged `*.sql` files, re-staging only those (the commit is blocked if a staged `*.sql` file also has unstaged changes), then SQL style lint | `sqlfluff fix -- <staged *.sql files>`, then `sqlfluff lint .` |
| `*.yaml / *.yml / *.json / *.template` containing `AWSTemplateFormatVersion` + `cfn-lint` on PATH | CloudFormation lint | `cfn-lint <changed files>` |

All triggered checks must pass. Missing tools are skipped silently.
The commit is blocked on the first failure.

### Super-linter equivalent (`.pre-commit-config.yaml`)

Mirrors the super-linter `VALIDATE_*` configuration, run by `pre-commit` against
staged files only (equivalent to `VALIDATE_ALL_CODEBASE: false`).

Every hook is a `repo: local` hook declared `language: system`, so pre-commit
installs nothing itself and each tool must be on `PATH`:

| VALIDATE_* | Tool | File trigger |
| --- | --- | --- |
| `VALIDATE_JSON` / `VALIDATE_XML` / `VALIDATE_YAML` (syntax) | `check-json` / `check-xml` / `check-yaml` (from the `pre-commit-hooks` pip package) | `*.json` / `*.xml` / `*.yaml/yml` |
| `VALIDATE_BASH` | `shellcheck` | Shell scripts (by extension or shebang) |
| `VALIDATE_BASH` (shell libraries) | `shellcheck` (via `run-shellcheck-libraries`) | Extensionless text files whose first line is a `# shellcheck shell=...` directive |
| `VALIDATE_YAML` (style) | `yamllint` | `*.yaml/yml` |
| `VALIDATE_PYTHON` | `flake8` | `*.py` |
| `VALIDATE_MD` | `markdownlint` | `*.md` (except `CHANGELOG.md`) |
| `VALIDATE_ANSIBLE` | `ansible-lint` | Every commit (scans the project itself) |
| `VALIDATE_DOCKERFILE` + `VALIDATE_DOCKERFILE_HADOLINT` | `hadolint` | `Dockerfile*` |
| `VALIDATE_GITHUB_ACTIONS` | `actionlint` | `.github/workflows/*.yml/yaml` |
| `VALIDATE_GITHUB_ACTIONS` (composite actions) | `composite-action-lint` | `.github/actions/*.yml/yaml` |
| `VALIDATE_PYTHON_PYLINT` | `pylint` (via `run-pylint`) | `*.py` |
| `VALIDATE_CSS` | `stylelint` (via `run-stylelint`) | `*.css` (skips if no `package.json`) |
| `VALIDATE_ENV` | `dotenv-linter` | `.env` / `.env.*` |
| `VALIDATE_TYPESCRIPT_ES` | `eslint` (via `run-eslint`) | `*.ts/tsx/js/jsx` (skips if no eslint config) |
| `VALIDATE_XML` (full) | `xmllint` | `*.xml` |
| `VALIDATE_POWERSHELL` | `pwsh` + `PSScriptAnalyzer` (via `run-psscriptanalyzer`) | `*.ps1/psm1/psd1` |
| `VALIDATE_BATS` | `bats` (via `run-bats`, runs only the `test/` files the staged files affect) | Staged shell scripts and `src/.pre-commit-config.yaml`, when `test/` holds a `*.bats` file (see [Bats test selection](#bats-test-selection-run-bats)) |
| `VALIDATE_SQLFLUFF` | None | Handled by dedicated SQL check |
| `VALIDATE_CLOUDFORMATION` | None | Handled by dedicated CFN check |

Both shellcheck hooks follow every `source` they can resolve and lint the
sourced file as well, including files outside the repository such as
`/etc/profile`, so results can differ between machines. A script that sources
a system or third-party file it cannot fix should put
`# shellcheck source=/dev/null` on the line above that `source` to opt the file
out; `# shellcheck disable=SC1091` does not.

**Additional security checks** (not part of the Super-linter `VALIDATE_*` set, added independently; tool must be on PATH):

| Check | Tool | File trigger |
| --- | --- | --- |
| Dependency vulnerabilities | `trivy fs --scanners vuln` | `package-lock.json`, `packages.lock.json`, `go.sum`, `requirements*.txt`, `Gemfile.lock`, `poetry.lock`, `Pipfile.lock` |
| Compose volume mount mode typos (e.g. `:r` instead of `:ro`) | `check-compose-volumes` (bundled, no external tool) | `docker-compose*.yml/yaml`, `compose*.yml/yaml` |
| Backslash used as a path separator in MSBuild files | `check-msbuild-path-separator` (bundled, no external tool) | `*.props`, `*.targets`, `*.csproj`, `*.slnx` |

`trivy`'s secret scanner is deliberately not enabled, because it would duplicate the
verified-only `trufflehog` check above with noisier, unverified findings.

#### Bats test selection (`run-bats`)

This section is the authoritative description of which files trigger the bats
hook and which bats files `run-bats` then runs. The code lives in
`src/scripts/run-bats` (`_bats_file_qualifies`, `_bats_map_files`,
`_bats_map_direct`, `_bats_naming_files`, `_bats_add_aliases`,
`_bats_deletion_qualifies` and the loop that calls them).

The bats hook has no file filter: pre-commit passes it every staged text file
and `run-bats` decides what to run. Running "the whole suite" below means
`bats --recursive test/`.

`run-bats` first exits 0 without running anything when `test/` (searched
recursively) holds no `*.bats` file, whatever its arguments. In a repository
without bats tests the hook therefore shows `Passed` rather than `Skipped`,
because it runs and exits at once without invoking `bats`.

A file **qualifies** when it is:

- named with a `.sh`, `.bash`, `.bats`, `.ksh` or `.dash` extension (so
  `test/test_helper.bash` qualifies, and so does a deleted file with one of
  these extensions);
- an existing file whose first line is a shebang naming `sh`, `bash`, `dash`,
  `ksh` or `busybox sh` in `/bin`, `/usr/bin` or `/usr/local/bin`, directly or
  through `env` or `env -S`;
- an existing file whose first line is a `# shellcheck shell=...` directive
  for `sh`, `bash`, `dash`, `ksh` or `busybox`; or
- `src/.pre-commit-config.yaml`.

Every other file (for example `README.md`) is ignored. A deleted file passed
by hand with no qualifying extension is ignored too, because there is no
first line left to read; staged deletions are handled separately, below.

`run-bats <file>...` maps each qualifying file to the bats files it affects
and runs only those. Paths are resolved relative to the repository root, so
an absolute path inside the repository maps like a relative one. Only a
path's directory is resolved, and only for an absolute path or one with an
empty, `.` or `..` component, so a symlink maps by its own path and basename,
not by its target's. Every qualifying file is mapped at once: one search finds
the naming files of all of them, and one finds the tests naming any of their
basenames. pre-commit passes only the path that changed, so every
symlink in the repository (tracked, or untracked and not ignored) that points
at a passed file is mapped as a changed file too: changing
`src/scripts/alpha-tool.sh` also runs the tests of a
`src/scripts/alias-tool.sh -> alpha-tool.sh`, since the symlink now behaves
differently. Such a symlink under `test/` therefore runs the whole suite, and
so does one that maps to no bats file. A file reached through a symlinked
directory is not found, since git lists no path below one:

- a `test/**/*.bats` file that exists runs itself;
- any other file runs `test/<basename without its last extension>.bats` if
  that file exists, plus every `.bats` file under `test/` (searched
  recursively, in the working tree, so untracked tests count) whose text
  contains the file's basename (a test naming the repo-relative path contains
  the basename, so it matches too);
- such a file also runs, one level up, the tests of every **naming file**: a
  qualifying file anywhere in the repository (tracked or untracked, not
  ignored; symlinks are not read) other than itself whose text names its
  basename, such as a script that runs or sources it or
  `src/.pre-commit-config.yaml` naming it as a hook `entry:`. Its tests run
  through the naming file, so changing `src/scripts/check-ignored-files` also
  runs the tests of `src/hooks/pre-commit`, which runs it. Each naming file
  maps by the rules above and below, but its own naming files are not
  followed. The basename must stand alone, preceded by a line start, space,
  `/`, `=` or quote and followed by a line end, space, quote, `;` or `)`, so
  a line naming `lib/my-util.sh` does not make it a naming file of
  `util.sh`. A file that does not qualify, such as `README.md`, is never a
  naming file. A path built from variables (for example
  `. "$LIB_DIR/$name.sh"`) names no basename and is not found;
- the whole suite runs instead when any qualifying file, or any of its
  naming files, is one of:
  - a `.bats` file under `test/` that no longer exists (deleted or renamed);
  - any other file under `test/`, such as `test/test_helper.bash`;
  - a `.bats` file outside `test/`;
  - `src/.pre-commit-config.yaml`;
  - a file outside the repository;
  - a file that maps to no bats file by the first two rules above (so a
    library sourced only by scripts that have no tests still runs the whole
    suite).

A `.bats` file under `test/` that checks the repository as a whole, rather
than the scripts it names, can opt in to every narrowed run with a whole line
`# run-bats: always` (`test/mode-arg-convention.bats` does this, since it scans
every script under `src/scripts/`). `run-bats` adds such a file whenever it
runs a narrowed set of tests; it never makes a run start when no file
qualifies, and a whole-suite run includes it anyway.

pre-commit never passes a deleted file to a hook, so before mapping,
`run-bats <file>...` also reads the deletions of the change the passed files
come from (through `git_change_name_status` in
`src/scripts/lib/mode-arg.sh`, which runs `git diff --name-status
--no-renames`, so a rename counts as a deletion of its old name):

- on a `pre-commit run --from-ref A --to-ref B` run (which a `pre-push` hook
  runs too), pre-commit sets `PRE_COMMIT_FROM_REF` and `PRE_COMMIT_TO_REF`,
  and the change is the range from the merge base of `A` and `B` to `B`, the
  same range pre-commit took the files from; the index is not read;
- on any other run the change is the index against `HEAD`, and its deletions
  count only when every passed file is added or modified in the index, as on
  a commit. `pre-commit run --files` and `--all-files` pass files the index
  does not change, so a deletion left staged does not make them run the whole
  suite.

It then runs the whole suite instead, even when no passed file qualifies, if
any of those deletions:

- is under `test/`;
- has a qualifying extension or is `src/.pre-commit-config.yaml`; or
- had a qualifying first line before the change (in `HEAD`, or in the
  range's merge base), so a deleted extensionless script such as
  `src/scripts/run-bats` counts and a deleted `README.md` does not, or that
  content cannot be read (for example, a blob missing from a partial clone).

The whole suite also runs when the change cannot be read (for example, an
unreadable index). This check looks at the whole change, so when pre-commit
chunks the file list (see below) only one call makes the decision: the one
passed the change's designated file, the first file the change adds or
modifies that pre-commit passes to the hook (an existing regular file, not a
symlink, that is text by pre-commit's own test). Every other chunk is mapped
as usual, so a large rename commit runs the whole suite once rather than once
per chunk. On a `pre-commit run --files` run that passes only some of the
staged files, a deletion therefore counts only when the designated file is
among them.

When no passed file qualifies and no deletion triggers the whole suite,
`run-bats` exits 0 without running `bats`.

Other ways to run the whole suite:

- `RUN_BATS_FULL=1 run-bats <file>...` skips the mapping and runs the whole
  suite, provided at least one passed file qualifies (otherwise it still exits
  0 without running `bats`);
- `run-bats --all-files` runs the whole suite when any tracked file
  (`git ls-files`) qualifies, and otherwise exits 0;
- `run-bats` with no arguments runs the whole suite unconditionally.

`pre-commit run --all-files` passes every tracked text file rather than the
`--all-files` flag, so each file is mapped as above; every tracked `test/`
bats file still runs, because each maps to itself. pre-commit splits a very
long file list into chunks by argument length and calls `run-bats` once per
chunk, so each chunk is mapped on its own. A chunk holding no qualifying file
runs nothing, unless it holds the designated file of a change whose deletion
triggers the whole suite (see above), in which case that one chunk runs the
whole suite.

---

## Baseline mode (`--all-files`)

Run the full check suite against the whole tracked tree, independent of
whatever is (or isn't) staged, with:

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
| Ignored-file / `src/FunFair.props` / dotnet-tools.json / install-location / freshness guards | Runs | Runs (unchanged) |
| `pre-commit run` | Staged files only | `--all-files` |
| Changelog / .NET / NPM / SQL / CloudFormation category checks | Gated on staged files | Gated on tracked files |

Auto-fixers (`sqlfluff fix`, the .NET formatter, `clean-package-lock-registry`,
and, in `--all-files` mode only, `check-changelog`'s `--lint --fix`) still
run and re-stage what they change, against the wider file list rather than
only what's staged: the point of `--all-files` is to detect *and fix* every
issue across the tracked tree with no commit in progress, not just to report
on it.

The protected/linter-config-file guards (blocking staged changes to
`.shellcheckrc`, `.ai-instructions`, `ai/global/`, etc.) still key off
whatever is staged, in both modes: they guard commit *content*, not the
tracked tree, so they are unaffected by `--all-files`.

An unrecognised argument is rejected with a non-zero exit and an error
message; the default no-argument invocation is unaffected by this mode.

---

## What is always blocked

`pre-push` unconditionally blocks all pushes regardless of repo or content.

---

## Installing optional tools

Use the provided dependency scripts (see [Dependencies](#dependencies) above).
They handle all system tools, install them idempotently, and are safe to re-run
after updates.

After installing any tool, re-run `./install` to see the updated status table.
Every hook is `language: system`, so hook tool versions are whatever is
installed on the system: update them through the dependency scripts or the
system package manager rather than `pre-commit autoupdate`.

---

## Scripts

| Script | Source |
| --- | --- |
| `scripts/buildtest` | Vendored from [credfeto/scripts: buildtest](https://github.com/credfeto/scripts/blob/main/development/buildtest) |
| `scripts/benchmark-test-affected` | Local addition, decides which benchmark test projects `buildtest`'s separate benchmark-only test step should run, from staged git changes alone (no `dotnet` required) |
| `scripts/check-benchmark-project-names` | Local addition, fails when a project containing BenchmarkDotNet benchmarks is not named `<Name>.Benchmark.Tests` or does not use that namespace (no `dotnet` required) |
| `scripts/latest-target-framework` | Local addition, prints a multi-targeted `.csproj`'s latest target framework moniker so `buildtest`'s benchmark test step can restrict itself to it (older frameworks are assumed to work); prints nothing for a single-targeted project (no `dotnet` required) |
| `scripts/buildcheck` | Vendored from [credfeto/scripts: buildcheck](https://github.com/credfeto/scripts/blob/main/development/buildcheck) |
| `scripts/check-ignored-files` | Port of [check-no-ignored-files](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-ignored-files/action.yml) |
| `scripts/check-funfair-props` | Local addition, removes `src/FunFair.props` from repositories whose `origin` remote is not owned by `funfair-tech` |
| `scripts/check-merge-commits` | Port of [check-no-merge-commits](https://github.com/funfair-tech/funfair-server-template/blob/main/.github/actions/check-no-merge-commits/action.yml) |
| `scripts/run-eslint` | Wrapper for eslint; skips silently if no `package.json` or eslint config |
| `scripts/run-stylelint` | Wrapper for stylelint; skips silently if no `package.json` |
| `scripts/run-psscriptanalyzer` | Wrapper for PSScriptAnalyzer; runs per-file via pwsh |
| `scripts/run-shellcheck-libraries` | Wrapper for shellcheck that lints extensionless, shebang-less shell libraries whose first line is a `# shellcheck shell=...` directive |
| `scripts/run-bats` | Wrapper for bats, runs the `test/` files the staged files affect, or the whole suite when they cannot be narrowed down (see [Bats test selection](#bats-test-selection-run-bats)) |
| `scripts/run-pylint` | Wrapper for pylint, runs it from a cached venv layered on the system pylint when the repo declares Python dependencies (`requirements.txt` or `pyproject.toml`) so the repo's own imports resolve, otherwise runs system pylint directly |
| `scripts/run-formatter` | Applies `dotnet format` to staged `.cs` files and then `cscleanup` (`Credfeto.DotNet.Repo.Formatter`) to staged `.cs`/`.csproj` files (every tracked one in `--all-files` mode), re-staging what it changes |

---

## Two-layer enforcement

| Layer | Mechanism | Blocks |
| --- | --- | --- |
| [GitHub API proxy](https://github.com/dnyw4l3n13/github-api-proxy) | HTTP 403 on git Data API / git-receive-pack / GraphQL git mutations | Programmatic commits via REST or GraphQL |
| These hooks (`core.hooksPath`) | exit 1 on pre-commit / pre-push | Local `git commit` and `git push` |
