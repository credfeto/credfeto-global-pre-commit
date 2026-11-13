#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

# entry is the script's absolute path (not a bare name) because these tests
# invoke `pre-commit run` directly rather than going through src/hooks/pre-commit
# (which puts SCRIPTS_DIR on PATH) — see the check-msbuild-path-separator
# section below for why.
CHECK_MSBUILD_PATH_SEPARATOR_CONFIG="repos:
  - repo: local
    hooks:
      - id: check-msbuild-path-separator
        name: check-msbuild-path-separator
        entry: ${REPO_DIR}/src/scripts/check-msbuild-path-separator
        language: system
        files: \\.(props|targets|csproj|slnx)\$
"

# ── check-msbuild-path-separator ─────────────────────────────────────────────
# Invoked via `pre-commit run` directly (not run_hook, the full src/hooks/pre-commit
# wrapper) because *.csproj/*.props/*.targets/*.slnx are also DOTNET_CHANGES
# triggers there, so a fixture that passes this hook cleanly would otherwise
# fall through into the .NET buildcheck/buildtest stage and fail on tooling
# these tests have no need of. Going through the real pre-commit framework
# (rather than invoking the script directly) still satisfies
# ai/local/linters.instructions.md rule 3 (each test exercises a project-level
# .pre-commit-config.yaml scoped to this linter alone) and is what caught
# Phase A's "hook never registered in src/.pre-commit-config.yaml" bug, which
# direct invocation could not have caught.

# run_msbuild_hook <repo dir> <file to check>
# Runs pre-commit directly against the given file in <repo dir>, bypassing
# src/hooks/pre-commit. Sets $status/$output via bats' run.
run_msbuild_hook() {
    local _t="$1"
    local _file="$2"
    run bash -c 'cd "$1" && pre-commit run check-msbuild-path-separator --config .pre-commit-config.yaml --files "$2"' _ "${_t}" "${_file}"
}

@test ".csproj file with backslash path separator is rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-backslash-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <PropertyGroup>\n    <LicensePath>$(MSBuildThisFileDirectory)..\\LICENSE</LicensePath>\n    <ResultsDir>$(SolutionDir)\\..\\results\\output</ResultsDir>\n  </PropertyGroup>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file using forward slashes, with a PackagePath root marker (no match) and an excluded comment, passes" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-forward-slash-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <PropertyGroup>\n    <LicensePath>$(MSBuildThisFileDirectory)../LICENSE</LicensePath>\n  </PropertyGroup>\n  <ItemGroup>\n    <None Include="results/output.txt" PackagePath="\\" />\n  </ItemGroup>\n  <!-- Bad: $(SolutionDir)\\..\\results - use forward slashes instead -->\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 0 ]
}

@test ".csproj file with a real violation on the same line as a PackagePath root marker is still rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-packagepath-violation-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <ItemGroup>\n    <None Include="$(OutDir)\\extra.dll" PackagePath="\\" />\n  </ItemGroup>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file with a real violation sharing a line with a trailing comment is still rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-trailing-comment-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <PropertyGroup>\n    <LicensePath>$(MSBuildThisFileDirectory)..\\LICENSE</LicensePath> <!-- keep this --> \n  </PropertyGroup>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file with an ordinary mid-path backslash (no leading .. or preceding paren) is rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-mid-path-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf '<Project>\n  <ItemGroup>\n    <Reference Include="Foo">\n      <HintPath>packages\\Foo.1.0.0\\lib\\net45\\Foo.dll</HintPath>\n    </Reference>\n  </ItemGroup>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file with a chain of macro references separated by backslashes is rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-macro-chain-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <ItemGroup>\n    <Import Project="$(A)\\$(B)\\$(C)" />\n  </ItemGroup>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file with a backslash right before a macro reference (no preceding path-segment char) is rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-backslash-before-macro-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <ItemGroup>\n    <Import Project="\\$(SolutionDir)Common.targets" />\n  </ItemGroup>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file with a violation sandwiched between two single-line comments on the same line is still rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-double-comment-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <!-- a --> <LicensePath>$(SolutionDir)\\..\\bad</LicensePath> <!-- b -->\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".csproj file with a backslash path only inside a multi-line comment passes" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-multiline-comment-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <!--\n    Bad example: $(SolutionDir)\\..\\results\n  -->\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 0 ]
}

@test ".csproj file with a real violation right after a multi-line comment closes on the same line is still rejected" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-multiline-comment-close-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # shellcheck disable=SC2016
    printf '<Project>\n  <!--\n    doc text\n  --> <LicensePath>$(SolutionDir)\\..\\bad</LicensePath>\n</Project>\n' > "${T}/Sample.csproj"
    git -C "${T}" add .pre-commit-config.yaml Sample.csproj
    run_msbuild_hook "${T}" Sample.csproj
    [ "${status}" -eq 1 ]
}

@test ".sln file with backslash-separated project paths (the dotnet sln/Visual Studio convention) is not scanned by this hook" {
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/msbuild-sln-excluded-test)"
    printf '%s' "${CHECK_MSBUILD_PATH_SEPARATOR_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Foo", "..\\Foo\\Foo.csproj", "{5A00799E-8CAD-4314-BC22-C44FB9571FD7}"\n' > "${T}/Sample.sln"
    git -C "${T}" add .pre-commit-config.yaml Sample.sln
    run_msbuild_hook "${T}" Sample.sln
    [ "${status}" -eq 0 ]
}
