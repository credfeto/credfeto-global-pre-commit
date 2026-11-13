#!/usr/bin/env bats
# Acceptance tests for the .NET formatter step: src/scripts/lib/dotnet-format.sh
# (format_dotnet_sources) and how src/scripts/buildtest runs it between its
# single solution restore and its build. Verifies that dotnet format gets
# --include paths relative to the repository root and runs from there (an
# absolute path matches nothing, so the fix is silently skipped), that it
# runs with --no-restore after buildtest's restore and falls back to a normal
# run when no restore has happened, that cscleanup runs after it, and that
# the fixed files are re-staged before the build.
#
# Uses a stubbed `dotnet` on PATH, so no real SDK, cscleanup or dotnet-format
# installation is required. The stub logs every call, and its `format`
# behaves like the real one on SDK 11: it fixes a `var` declaration in each
# --include path that exists relative to its working directory, and matches
# nothing for an absolute path.

load test_helper

bats_require_minimum_version 1.5.0

BUILDTEST="${REPO_DIR}/src/scripts/buildtest"
LIB="${REPO_DIR}/src/scripts/lib/dotnet-format.sh"
MODE_LIB="${REPO_DIR}/src/scripts/lib/mode-arg.sh"

# Writes a stub `dotnet` to <dir>/dotnet that logs each call to <log> as one
# line (the subcommand and its arguments, space-separated) and succeeds. It
# reports a pre-release SDK, so buildtest skips its benchmark step, lists
# cscleanup as an installed tool, and its `format` logs its working
# directory on a `format-cwd` line before fixing the --include files.
make_dotnet_stub() {
    local _dir="$1"
    local _log="$2"
    mkdir -p "${_dir}"
    cat > "${_dir}/dotnet" << STUB
#!/bin/sh
_log="${_log}"
log_call() {
    printf '%s' "\$1" >> "\${_log}"
    shift
    for _a in "\$@"; do printf ' %s' "\${_a}" >> "\${_log}"; done
    printf '\n' >> "\${_log}"
}
case "\$1" in
    --version)
        printf '11.0.100-rc.3\n'
        ;;
    tool)
        printf 'Package Id                        Version      Commands\n'
        printf -- '-------------------------------------------------------\n'
        printf 'credfeto.dotnet.repo.formatter    1.0.0        cscleanup\n'
        ;;
    format)
        [ "\$2" = "--version" ] && { printf '11.0.100\n'; exit 0; }
        shift
        log_call format "\$@"
        printf 'format-cwd %s\n' "\$(pwd)" >> "\${_log}"
        _in_include=0
        for _a in "\$@"; do
            case "\$_a" in
                --include) _in_include=1; continue ;;
                --*) _in_include=0; continue ;;
            esac
            [ "\$_in_include" = 1 ] || continue
            case "\$_a" in
                /*) ;;
                *) [ -f "\$_a" ] && sed -i 's/var value =/int value =/' "\$_a" ;;
            esac
        done
        ;;
    *)
        log_call "\$@"
        ;;
esac
exit 0
STUB
    chmod +x "${_dir}/dotnet"
}

# Creates a plain git repo with a src/Foo.csproj and a src/Foo.cs holding a
# fixable style violation (`var` where an explicit type is required), and
# prints the repo path.
setup_repo() {
    local _t="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${_t}/src"
    git -C "${_t}" init --quiet
    git -C "${_t}" config user.email "test@example.com"
    git -C "${_t}" config user.name "Test User"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${_t}/src/Foo.csproj"
    printf 'class Foo { void M() { var value = 1; } }\n' > "${_t}/src/Foo.cs"
    printf '%s' "${_t}"
}

# Line number of the first line in <log> starting with <prefix>.
first_line() {
    grep -n "^$2" "$1" | head -1 | cut -d: -f1
}

# Runs format_dotnet_sources <solution> <restored> [mode-arg] from the repo
# in the current directory, with the stub dotnet in <stubdir> first on PATH.
run_format_dotnet_sources() {
    local _stubdir="$1"
    shift
    # shellcheck disable=SC2016 # intentionally literal — expanded by the inner sh, not here
    run env PATH="${_stubdir}:${TEST_PATH}" sh -c '
        die() { printf "DIED: %s\n" "$*"; exit 1; }
        info() { printf "%s\n" "$*"; }
        success() { printf "%s\n" "$*"; }
        require_dotnet_tool() { return 0; }
        . "$1"
        . "$2"
        parse_all_files_mode_arg "$5"
        format_dotnet_sources "$3" "$4"
    ' _ "${MODE_LIB}" "${LIB}" "$@"
}

# ── buildtest ─────────────────────────────────────────────────────────────────

@test "buildtest fixes a staged .cs style violation and re-stages it before the build" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs src/Foo.csproj src/Foo.slnx

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0

    # Fixed in the working tree and in the index, so the commit gets it.
    grep -q 'int value = 1;' "${T}/src/Foo.cs"
    git -C "${T}" show :src/Foo.cs | grep -q 'int value = 1;'
    [ -z "$(git -C "${T}" diff --name-only)" ]
}

@test "buildtest restores once, then runs dotnet format --no-restore, then cscleanup, then builds" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs src/Foo.csproj src/Foo.slnx

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0

    [ "$(grep -c '^restore' "${LOG}")" -eq 1 ]
    grep -q '^format .* --no-restore ' "${LOG}"

    local _restore _format _cscleanup _build
    _restore=$(first_line "${LOG}" restore)
    _format=$(first_line "${LOG}" 'format ')
    _cscleanup=$(first_line "${LOG}" cscleanup)
    _build=$(first_line "${LOG}" build)
    [ "${_restore}" -lt "${_format}" ]
    [ "${_format}" -lt "${_cscleanup}" ]
    [ "${_cscleanup}" -lt "${_build}" ]
}

@test "buildtest passes dotnet format the solution and repo-relative --include paths, from the repo root" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    printf '\n' > "${T}/src/Foo.sln"
    git -C "${T}" add src/Foo.cs src/Foo.csproj src/Foo.slnx

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0

    local _format_line
    _format_line=$(grep '^format ' "${LOG}")
    # The .slnx is preferred over the .sln.
    [[ "${_format_line}" == "format ${T}/src/Foo.slnx "* ]]
    # Only the staged .cs file, never the .csproj, and never an absolute path.
    [[ "${_format_line}" == *" --include src/Foo.cs" ]]
    [[ "${_format_line}" != *"Foo.csproj"* ]]
    local _include
    _include="${_format_line##* --include }"
    [[ "${_include}" != /* ]]
    [[ "${_include}" != *" /"* ]]
    [ "$(grep '^format-cwd ' "${LOG}")" = "format-cwd ${T}" ]

    # cscleanup gets both staged files.
    local _cscleanup_line
    _cscleanup_line=$(grep '^cscleanup ' "${LOG}")
    [[ "${_cscleanup_line}" == *"${T}/src/Foo.cs"* ]]
    [[ "${_cscleanup_line}" == *"${T}/src/Foo.csproj"* ]]
}

@test "buildtest skips dotnet format for .csproj-only staged changes but still runs cscleanup" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.csproj src/Foo.slnx

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    run ! grep -q '^format ' "${LOG}"
    grep -q '^cscleanup ' "${LOG}"
}

@test "buildtest without a solution skips dotnet format and the build without failing, but still runs cscleanup" {
    local T
    T="$(setup_repo)"
    git -C "${T}" add src/Foo.cs src/Foo.csproj

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    run ! grep -q '^format ' "${LOG}"
    run ! grep -q '^build' "${LOG}"
    grep -q '^cscleanup ' "${LOG}"
}

@test "buildtest default mode skips a tracked but unstaged .cs file" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs src/Foo.csproj src/Foo.slnx
    git -C "${T}" commit --quiet --no-gpg-sign -m seed
    printf 'x\n' > "${T}/README.md"
    git -C "${T}" add README.md

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    run ! grep -q '^format ' "${LOG}"
    run ! grep -q '^cscleanup ' "${LOG}"
    grep -q 'var value = 1;' "${T}/src/Foo.cs"
}

@test "buildtest all-files mode formats and stages a tracked but unstaged .cs file" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs src/Foo.csproj src/Foo.slnx
    git -C "${T}" commit --quiet --no-gpg-sign -m seed

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}" --all-files

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    local _cscleanup_line
    _cscleanup_line=$(grep '^cscleanup ' "${LOG}")
    [[ "${_cscleanup_line}" == *"${T}/src/Foo.cs"* ]]
    git -C "${T}" show :src/Foo.cs | grep -q 'int value = 1;'
}

@test "buildtest rejects an unknown argument" {
    local T
    T="$(setup_repo)"
    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    PATH="${STUBDIR}:${TEST_PATH}" run sh "${BUILDTEST}" --bogus

    [ "${status}" -eq 1 ]
    [ ! -f "${LOG}" ]
}

# ── format_dotnet_sources ─────────────────────────────────────────────────────

@test "format_dotnet_sources runs dotnet format with --no-restore when the solution is restored" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}/src"
    run_format_dotnet_sources "${STUBDIR}" "${T}/src/Foo.slnx" 1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(grep '^format ' "${LOG}")" = "format ${T}/src/Foo.slnx --no-restore --include src/Foo.cs" ]
    git -C "${T}" show :src/Foo.cs | grep -q 'int value = 1;'
}

@test "format_dotnet_sources falls back to a restoring dotnet format run when no restore has happened" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    run_format_dotnet_sources "${STUBDIR}" "${T}/src/Foo.slnx" 0

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(grep '^format ' "${LOG}")" = "format ${T}/src/Foo.slnx --include src/Foo.cs" ]
    [[ "${output}" == *"no earlier restore"* ]]
    git -C "${T}" show :src/Foo.cs | grep -q 'int value = 1;'
}

@test "format_dotnet_sources does nothing when no .cs or .csproj file is staged" {
    local T
    T="$(setup_repo)"
    printf 'x\n' > "${T}/README.md"
    git -C "${T}" add README.md

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    local LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    make_dotnet_stub "${STUBDIR}" "${LOG}"

    cd "${T}"
    run_format_dotnet_sources "${STUBDIR}" "${T}/src/Foo.slnx" 1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ ! -f "${LOG}" ]
}

@test "format_dotnet_sources stages nothing when dotnet format fails" {
    local T
    T="$(setup_repo)"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    git -C "${T}" add src/Foo.cs

    local STUBDIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${STUBDIR}"
    cat > "${STUBDIR}/dotnet" << 'STUB'
#!/bin/sh
[ "$1" = "format" ] && [ "$2" != "--version" ] && {
    sed -i 's/var value =/int value =/' src/Foo.cs
    exit 1
}
exit 0
STUB
    chmod +x "${STUBDIR}/dotnet"

    cd "${T}"
    run_format_dotnet_sources "${STUBDIR}" "${T}/src/Foo.slnx" 1

    [ "${status}" -eq 1 ]
    [[ "${output}" == *"DIED: dotnet format failed"* ]]
    git -C "${T}" show :src/Foo.cs | grep -q 'var value = 1;'
}
