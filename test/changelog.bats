#!/usr/bin/env bats
# Acceptance tests for src/scripts/check-changelog:
# - lints staged CHANGELOG.md files via `dotnet changelog --lint`
# - in *-template repos, additionally rejects any CHANGELOG.md entries
#
# `dotnet changelog` is a local dotnet tool resolved by walking up the cwd
# from the repo under test; bats repos live under a tmp tree with no such
# ancestor manifest, so these tests run against a fake `dotnet` on PATH
# rather than the real tool (see fake_dotnet_path below).

load test_helper

CHECK_CHANGELOG="${REPO_DIR}/src/scripts/check-changelog"

# The exact blank skeleton `dotnet changelog` writes for a brand new file —
# used both as the fake tool's canned output and as a valid staged fixture.
PRISTINE_CHANGELOG='# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Security
### Added
### Fixed
### Changed
### Deprecated
### Removed
### Deployment Changes
<!--
Releases that have at least been deployed to staging, BUT NOT necessarily released to live.  Changes should be moved from [Unreleased] into here as they are merged into the appropriate release branch
-->
## [0.0.0] - Project created'

# Installs a fake `dotnet` at "$1/dotnet" that understands just enough of
# `tool list` and the `changelog` subcommand to drive check-changelog:
#   - `tool list` reports credfeto.changelog.cmd as installed
#   - `changelog --lint -f FILE` always reports success (lint correctness is
#     a pre-existing, separately covered concern — not under test here)
#   - `changelog -f FILE -a ... -m ...` (re)writes FILE to the pristine blank
#     skeleton, mirroring what the real tool produces for a fresh file
#   - `changelog -f FILE -r ... -m ...` and `--lint --fix` are no-ops, since
#     starting from the pristine skeleton they have nothing to do
fake_dotnet_path() {
    local _bin="$1"
    mkdir -p "${_bin}"
    printf '%s\n' "${PRISTINE_CHANGELOG}" > "${_bin}/pristine.md"
    cat > "${_bin}/dotnet" <<'FAKE_DOTNET_EOF'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then
    printf 'Package Id               Version  Commands   Manifest\n'
    printf 'credfeto.changelog.cmd   1.0.0    changelog  /fake\n'
    exit 0
fi
if [ "$1" = "changelog" ]; then
    shift
    FILE=""
    ADD=0
    LINT=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -f) FILE="$2"; shift 2 ;;
            -a) ADD=1; shift 2 ;;
            -r) shift 2 ;;
            -m) shift 2 ;;
            --lint) LINT=1; shift ;;
            --fix) shift ;;
            *) shift ;;
        esac
    done
    if [ "$ADD" -eq 1 ] && [ -n "$FILE" ]; then
        cp "$DIR/pristine.md" "$FILE"
        exit 0
    fi
    if [ "$LINT" -eq 1 ]; then
        printf 'Changelog is valid\n'
        exit 0
    fi
    exit 0
fi
exit 1
FAKE_DOTNET_EOF
    chmod +x "${_bin}/dotnet"
}

# Runs check-changelog inside "$1" with the fake dotnet from "$2" prepended
# to TEST_PATH. Sets $status and $output via bats run.
run_check_changelog() {
    local _repo="$1" _fake_bin="$2"
    run bash -c 'cd "$1" && env PATH="$2:$3" sh "$4"' \
        _ "${_repo}" "${_fake_bin}" "${TEST_PATH}" "${CHECK_CHANGELOG}"
}

setup() {
    FAKE_BIN="${BATS_TEST_TMPDIR}/fake_bin"
    fake_dotnet_path "${FAKE_BIN}"
}

# ── nothing staged ────────────────────────────────────────────────────────────

@test "no staged CHANGELOG.md passes" {
    local T
    T="$(make_repo feature/changelog-none-test)"
    printf 'hello\n' > "${T}/file.txt"
    git -C "${T}" add file.txt
    run_check_changelog "${T}" "${FAKE_BIN}"
    [ "${status}" -eq 0 ]
}

# ── template repos: blank enforcement ─────────────────────────────────────────

@test "blank CHANGELOG.md in a *-template repo passes" {
    local T
    T="$(make_repo feature/changelog-template-blank-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf '%s\n' "${PRISTINE_CHANGELOG}" > "${T}/CHANGELOG.md"
    git -C "${T}" add CHANGELOG.md
    run_check_changelog "${T}" "${FAKE_BIN}"
    [ "${status}" -eq 0 ]
}

@test "CHANGELOG.md with an entry in a *-template repo is rejected" {
    local T
    T="$(make_repo feature/changelog-template-entry-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    printf '%s\n' "${PRISTINE_CHANGELOG}" \
        | sed 's/^### Added$/### Added\n- Add a new feature/' \
        > "${T}/CHANGELOG.md"
    git -C "${T}" add CHANGELOG.md
    run_check_changelog "${T}" "${FAKE_BIN}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"must keep CHANGELOG.md blank"* ]]
}

@test "CHANGELOG.md with a release entry in a *-template repo is rejected" {
    local T
    T="$(make_repo feature/changelog-template-release-entry-test)"
    git -C "${T}" remote add origin "git@github.com:funfair-tech/funfair-server-template.git"
    printf '%s\n' "${PRISTINE_CHANGELOG}" \
        | sed 's/^## \[0.0.0\] - Project created$/## [1.0.0] - 2026-01-01\n### Fixed\n- Fixed a bug\n\n## [0.0.0] - Project created/' \
        > "${T}/CHANGELOG.md"
    git -C "${T}" add CHANGELOG.md
    run_check_changelog "${T}" "${FAKE_BIN}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"must keep CHANGELOG.md blank"* ]]
}

@test "differing preamble wording and version number in a *-template repo still passes" {
    local T
    T="$(make_repo feature/changelog-template-preamble-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/cs-template.git"
    cat > "${T}/CHANGELOG.md" <<'CHANGELOG_EOF'
# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Please ADD ALL Changes to the UNRELEASED SECTION and not a specific release
-->

## [Unreleased]
### Security
### Added
### Fixed
### Changed
### Deprecated
### Removed
### Deployment Changes
<!--
Releases that have at least been deployed to staging, BUT NOT necessarily released to live.  Changes should be moved from [Unreleased] into here as they are merged into the appropriate release branch
-->
## [1.0.0] - Project created
CHANGELOG_EOF
    git -C "${T}" add CHANGELOG.md
    run_check_changelog "${T}" "${FAKE_BIN}"
    [ "${status}" -eq 0 ]
}

@test "CHANGELOG.md with entries in a non-template repo passes (blank check does not apply)" {
    local T
    T="$(make_repo feature/changelog-nontemplate-entry-test)"
    git -C "${T}" remote add origin "git@github.com:credfeto/credfeto-global-pre-commit.git"
    printf '%s\n' "${PRISTINE_CHANGELOG}" \
        | sed 's/^### Added$/### Added\n- Add a new feature/' \
        > "${T}/CHANGELOG.md"
    git -C "${T}" add CHANGELOG.md
    run_check_changelog "${T}" "${FAKE_BIN}"
    [ "${status}" -eq 0 ]
}
