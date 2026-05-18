&#xFEFF;# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Security
### Added
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

### Fixed
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

### Deprecated
### Removed
### Deployment Changes

## [0.0.0] - Project created
