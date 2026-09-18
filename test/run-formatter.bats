#!/usr/bin/env bats
# Acceptance tests for src/scripts/run-formatter: verifies dotnet format runs
# on staged .cs files before cscleanup, restricted to .cs only, preferring
# .slnx over .sln for solution discovery, and skipping gracefully when no
# solution file is found. Uses a stubbed `dotnet` on PATH (logging its argv)
# so no real dotnet SDK, cscleanup, or dotnet-format installation is required.

load test_helper

bats_require_minimum_version 1.5.0

SCRIPT="${REPO_DIR}/src/scripts/run-formatter"

# Writes a stub `dotnet` to <dir>/dotnet that answers `tool list` with a row
# satisfying run-formatter's cscleanup require_dotnet_tool check, answers
# `format --version` successfully, and logs every `format`/`cscleanup`
# invocation's arguments (one line per call, space-separated) to <log>.
make_dotnet_stub() {
    local _dir="$1"
    local _log="$2"
    mkdir -p "${_dir}"
    cat > "${_dir}/dotnet" <<STUB
#!/bin/sh
case "\$1" in
    tool)
        printf 'Package Id                        Version      Commands\n'
        printf -- '-------------------------------------------------------\n'
        printf 'credfeto.dotnet.repo.formatter    1.0.0        cscleanup\n'
        ;;
    format)
        if [ "\$2" = "--version" ]; then
            printf '9.0.100\n'
        else
            shift
            printf 'format' >> "${_log}"
            for _a in "\$@"; do printf ' %s' "\${_a}" >> "${_log}"; done
            printf '\n' >> "${_log}"
        fi
        ;;
    cscleanup)
        shift
        printf 'cscleanup' >> "${_log}"
        for _a in "\$@"; do printf ' %s' "\${_a}" >> "${_log}"; done
        printf '\n' >> "${_log}"
        ;;
esac
exit 0
STUB
    chmod +x "${_dir}/dotnet"
}

# Creates a plain git repo with a stub dotnet on PATH, prints the repo path.
setup_repo() {
    local _t="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${_t}/src"
    git -C "${_t}" init --quiet
    git -C "${_t}" config user.email "test@example.com"
    git -C "${_t}" config user.name "Test User"
    printf '%s' "${_t}"
}

@test "dotnet format runs on staged .cs files before cscleanup, preferring .slnx over .sln" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    printf '\n' > "${T}/src/Foo.sln"
    printf 'class Foo {}\n' > "${T}/src/Foo.cs"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${T}/src/Foo.csproj"
    git -C "${T}" add src/Foo.cs src/Foo.csproj

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    [ -f "${LOG}" ]

    local _format_line
    _format_line=$(grep '^format ' "${LOG}")
    local _cscleanup_line
    _cscleanup_line=$(grep '^cscleanup ' "${LOG}")

    [ -n "${_format_line}" ]
    [ -n "${_cscleanup_line}" ]

    # format ran on the .slnx (not the .sln), included the staged .cs file,
    # and did not include the staged .csproj.
    [[ "${_format_line}" == *"${T}/src/Foo.slnx"* ]]
    [[ "${_format_line}" == *"${T}/src/Foo.cs"* ]]
    [[ "${_format_line}" != *"${T}/src/Foo.csproj"* ]]

    # cscleanup ran on both staged files.
    [[ "${_cscleanup_line}" == *"${T}/src/Foo.cs"* ]]
    [[ "${_cscleanup_line}" == *"${T}/src/Foo.csproj"* ]]

    # format ran before cscleanup.
    local _format_lineno
    _format_lineno=$(grep -n '^format ' "${LOG}" | head -1 | cut -d: -f1)
    local _cscleanup_lineno
    _cscleanup_lineno=$(grep -n '^cscleanup ' "${LOG}" | head -1 | cut -d: -f1)
    [ "${_format_lineno}" -lt "${_cscleanup_lineno}" ]
}

@test "dotnet format falls back to .sln when no .slnx exists" {
    local T
    T="$(setup_repo)"
    printf '\n' > "${T}/src/Foo.sln"
    printf 'class Foo {}\n' > "${T}/src/Foo.cs"
    git -C "${T}" add src/Foo.cs

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    local _format_line
    _format_line=$(grep '^format ' "${LOG}")
    [[ "${_format_line}" == *"${T}/src/Foo.sln"* ]]
}

@test "dotnet format is skipped for .csproj-only staged changes" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${T}/src/Foo.csproj"
    git -C "${T}" add src/Foo.csproj

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    run ! grep -q '^format ' "${LOG}"
    grep -q '^cscleanup ' "${LOG}"
}

@test "dotnet format is skipped without failing when no solution file exists" {
    local T
    T="$(setup_repo)"
    printf 'class Foo {}\n' > "${T}/src/Foo.cs"
    git -C "${T}" add src/Foo.cs

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    run ! grep -q '^format ' "${LOG}"
    grep -q '^cscleanup ' "${LOG}"
}

# ── all-files mode ────────────────────────────────────────────────────────────

@test "default mode skips a tracked but unstaged .cs file" {
    local T
    T="$(setup_repo)"
    printf 'class Foo {}\n' > "${T}/src/Foo.cs"
    git -C "${T}" add src/Foo.cs
    git -C "${T}" commit --quiet -m seed

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    [ ! -f "${LOG}" ]
}

@test "all-files mode formats and stages a tracked but unstaged .cs file" {
    local T
    T="$(setup_repo)"
    printf 'class Foo {}\n' > "${T}/src/Foo.cs"
    git -C "${T}" add src/Foo.cs
    git -C "${T}" commit --quiet -m seed

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}" --all-files

    [ "${status}" -eq 0 ]
    grep -q '^cscleanup ' "${LOG}"
    local _cscleanup_line
    _cscleanup_line=$(grep '^cscleanup ' "${LOG}")
    [[ "${_cscleanup_line}" == *"${T}/src/Foo.cs"* ]]
}

@test "run-formatter rejects an unknown argument" {
    local T
    T="$(setup_repo)"
    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${PATH}" run "${SCRIPT}" --bogus

    [ "${status}" -eq 1 ]
}
