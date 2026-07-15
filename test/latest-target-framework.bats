#!/usr/bin/env bats
# Acceptance tests for src/scripts/latest-target-framework, the pure
# file-analysis helper buildtest's benchmark test step uses to restrict a
# multi-targeted benchmark project to only its latest target framework.
# Invoked directly -- no dotnet required.

load test_helper

SCRIPT="${REPO_DIR}/src/scripts/latest-target-framework"

@test "a single-targeted project prints nothing" {
    local T="${BATS_TEST_TMPDIR}/Foo.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net9.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' \
        > "${T}"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "a project with no target framework element prints nothing" {
    local T="${BATS_TEST_TMPDIR}/Foo.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${T}"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "a multi-targeted project prints the highest version, out of order and double-digit-safe" {
    local T="${BATS_TEST_TMPDIR}/Foo.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFrameworks>net9.0;net10.0;net8.0</TargetFrameworks>\n  </PropertyGroup>\n</Project>\n' \
        > "${T}"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "net10.0" ]
}

@test "a TargetFrameworks element listing only one framework prints nothing" {
    local T="${BATS_TEST_TMPDIR}/Foo.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFrameworks>net9.0</TargetFrameworks>\n  </PropertyGroup>\n</Project>\n' \
        > "${T}"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "usage error when no csproj path is given" {
    run "${SCRIPT}"
    [ "${status}" -eq 1 ]
}

@test "usage error when the csproj path does not exist" {
    run "${SCRIPT}" "${BATS_TEST_TMPDIR}/does-not-exist.csproj"
    [ "${status}" -eq 1 ]
}
