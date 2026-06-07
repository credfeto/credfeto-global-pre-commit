&#xFEFF;# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Security
### Added
- Add acceptance tests for check-shebang-scripts-are-executable hook covering pass and fail cases (#75)
- Add acceptance tests for check-json hook covering pass and fail cases (#74)
- Add acceptance tests for check-yaml hook covering pass and fail cases (#77)
- Add acceptance tests for markdownlint hook covering pass and fail cases (#80)
- Fail pre-commit when hooks repo is out of date and AI agent does not have write access to update it (#26)
- csharpier: apply formatting fix to staged .cs files and re-stage after formatting, replacing the previous read-only check (#19)
- csharpier format check as pre-commit step (#17)
- Changelog lint step: lint staged CHANGELOG.md files using dotnet changelog tool
- Block direct commits to main/master branch in pre-commit hook; tailor message for AI agent sessions (#9)
- Abort pre-commit hook when nothing is staged to prevent empty commits
- Normalise private registry URLs in staged package-lock.json files (#4)
- Installation scripts for Arch Linux and Debian/Ubuntu
- NVM installation via package repo in dependency scripts
- Comprehensive install.sh with tool check-status table
- add .markdownlintignore to exclude CHANGELOG.md from markdown linting
- Acceptance test script to verify pre-commit hook orchestration with isolated temporary repositories
- Auto-detect Arch-based or Debian-based Linux in install and run the appropriate install-deps script automatically
- GitHub Actions workflow to install dependencies, run acceptance tests, and always clean up the global pre-commit hooks on the runner
- Added acceptance tests for PSScriptAnalyzer (pwsh) linter hook covering pass and fail cases
- Add acceptance tests for xmllint hook to verify well-formed XML passes and malformed XML is rejected (#89)
- Add acceptance tests for eslint linter
- Add acceptance tests for actionlint hook
- Environment sanity checks: reject commits if dotnet is found at $HOME/.dotnet/dotnet (corrupt install) or if dotnet on PATH does not resolve to /usr/share/dotnet/dotnet
- Added acceptance tests for stylelint hook (pass and fail cases)
- Added pass/fail acceptance tests for composite-action-lint hook
- Acceptance tests for pylint hook (pass and fail cases)
- Added acceptance tests for ansible-lint hook (pass and fail cases)
- Add acceptance tests for flake8 linter hook covering pass and fail cases (#82)
- Compare installed SHA (from .env) against the published URL when curl is available; die if stale (result cached for one hour) (#113)
- Added acceptance tests for hadolint Dockerfile linter hook covering pass and fail cases
- Add acceptance tests for shellcheck hook covering pass and fail cases (#79)
- Use bats for acceptance tests
- Add bats pre-commit hook to run bats tests when .bats files are staged
- Add acceptance tests for yamllint hook covering pass and fail cases (#78)
- install: --system option to install hooks as system-wide git configuration (all users on the machine) using sudo git config --system
- Add acceptance tests for check-xml hook covering pass and fail cases (#76)
- Add acceptance tests for trufflehog hook covering pass and fail cases (#73)
- Add acceptance tests for check-executables-have-shebangs hook covering pass and fail cases (#72)
- Add acceptance tests for trailing-whitespace hook
- Acceptance tests for check-toml hook (pass and fail cases)
- Add acceptance tests for detect-private-key hook covering pass and fail cases (#69)

### Fixed
- Run sqlfluff lint after sqlfluff fix to catch violations that cannot be auto-fixed (#120)
- Invoke changelog tool directly rather than via dotnet prefix (#16)
- install.sh chmod list out of sync after check-secrets was inlined (#15)
- Use CLAUDECODE=1 env var (not CLAUDE) to detect Claude Code agent sessions
- Suppress trufflehog output on clean scans
- Only block direct pushes to main/master; allow all other branches (#5)
- Repair ansible-lint crash; relax markdownlint line-length rule (#2)
- remove .pre-commit-config.yaml from .gitignore as this repo is its source — was tracked but ignored
- buildtest now skips repos with no .csproj files rather than failing
- all shell scripts now use the correct die/info/success helper implementations with ANSI colour output
- buildtest: always restore ruleset file on exit, even when a die error occurs
- hadolint: ignore DL3018 by using the existing config at .github/linters/.hadolint.yaml
- Simplified check-ignored-files output parsing by removing verbose flag from git check-ignore and replacing awk with sed
- buildtest publish now iterates over all TargetFrameworks, passing --framework for each; dies early if no framework is specified in the csproj
- Use dotnet tool list to detect dotnet tools rather than command -v so local tool manifest installs are found
- dotnet_tool_installed now checks both command name and package ID columns in dotnet tool list output; all install suggestions now use --local with the package ID; version check removed from check-changelog
- dotnet_tool_installed now requires command name and package ID to match on the same row using awk, preventing false positives from independent column matches
- Remove duplicate buildcheck call from buildtest — buildcheck is invoked separately by the pre-commit hook
- Fix incorrect package IDs in dotnet_tool_installed calls: buildcheck is FunFair.BuildCheck and code-analysis is Credfeto.DotNet.Code.Analysis.Overrides.Cmd
- Removed shellcheck suppression comments and fixed underlying issues: used while/read loops and xargs in place of unquoted variable expansion, and added .shellcheckrc with external-sources=true to allow following sourced files
- dotenv-linter entry updated to use check subcommand for v4 compatibility
- end-of-file-fixer no longer modifies CHANGELOG.md, which is owned by the dotnet changelog tool
- install-deps-debian: fall back to pipx for pylint on Ubuntu 24.04 where python3-pylint apt package was removed
- install-deps-debian: use lowercase hadolint-linux-ARCH asset name for hadolint v2.14.0+
- install-deps-debian: fix dotenv-linter asset template to use x86_64/aarch64 (UARCH) naming
- Fixed substitution order in install_github_release so UARCH is expanded before ARCH, preventing UARCH from being mangled into Uamd64
- install_github_release: use python3 JSON parsing for GitHub releases/latest to handle minified API responses reliably
- Set DOTNET_ROLL_FORWARD=Major when running dotnet tsqllint to allow roll-forward to newer .NET runtimes (#101)
- Corrected Arch Linux package names in install-deps-arch: bash-bats renamed to bats, python-pre-commit renamed to pre-commit
- Fix run-bats failing with bats 1.10.x on Ubuntu 24.04 by exporting bats_readlinkf so the inner bats library can locate bats-exec-test correctly

### Changed
- Replaced csharpier with Credfeto.DotNet.Repo.Formatter (cscleanup) for C# formatting in pre-commit hooks
- Extended cscleanup formatter to also process staged .csproj files
- Pass all staged files to cscleanup in a single invocation rather than one call per file
- Replace custom check-secrets script with official TruffleHog pre-commit hook (#13)
- Make every pre-commit hook language: system, dropping managed virtual environments (#3)
- Remove husky delegation; pre-commit hook is now the sole orchestrator (#10)
- Exclude .github directory from ansible-lint (#7)
- Extract is_ai_agent helper to centralise CLAUDECODE detection
- Extract shared helpers into lib/common.sh
- Extract install_github_release helper in dependency scripts
- Install nvm from package repo rather than a custom curl function
- Only run npm steps when node is active in nvm
- align ai/local/index.md with cs-template standard (blank line before list, git URLs in backticks)
- buildtest: removed unused command-line argument parsing; hardcoded http-cache clear and release ruleset
- buildtest: publish each project with IsPublishable=true after testing
- split actionlint to workflows only; add composite-action-lint hook for .github/actions
- hooks freshness check: support stripped installs with HEAD/UPSTREAM from .env when .git is absent
- Renamed install.sh, install-deps-arch.sh, and install-deps-debian.sh to remove .sh extension, matching the no-extension convention used by scripts in scripts/
- sqlfluff check now runs fix (auto-correcting style violations) and re-stages any modified files; exports SQLFLUFF_EXECUTED so local scripts can skip a redundant run

### Deprecated
### Removed
### Deployment Changes

## [0.0.0] - Project created