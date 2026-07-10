#!/usr/bin/env bats
# Acceptance tests for src/scripts/dacpac-only-solution, the pure file-analysis
# helper buildtest uses to decide whether the solution's only project is a
# SQL Server database project (dacpac) — in which case there is nothing
# testable and `dotnet test` should be skipped. Invoked directly — no dotnet
# required.

load test_helper

SCRIPT="${REPO_DIR}/src/scripts/dacpac-only-solution"

@test "a solution whose only project is a dacpac is detected" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Database"
    printf '<Project Sdk="MSBuild.Sdk.SqlProj/2.5.0"></Project>\n' \
        > "${T}/src/Foo.Database/Foo.Database.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
}

@test "a solution whose only project is a normal SDK-style project is not a dacpac" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Library"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Library/Foo.Library.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 1 ]
}

@test "a solution with a dacpac plus another project is not treated as dacpac-only" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Database" "${T}/src/Foo.Migrations"
    printf '<Project Sdk="MSBuild.Sdk.SqlProj/2.5.0"></Project>\n' \
        > "${T}/src/Foo.Database/Foo.Database.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Migrations/Foo.Migrations.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 1 ]
}

@test "a solution with no .csproj files is not treated as dacpac-only" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 1 ]
}

@test "generated .csproj-like files under obj/bin are ignored" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Database/obj" "${T}/src/Foo.Database/bin"
    printf '<Project Sdk="MSBuild.Sdk.SqlProj/2.5.0"></Project>\n' \
        > "${T}/src/Foo.Database/Foo.Database.csproj"
    printf 'stray\n' > "${T}/src/Foo.Database/obj/Foo.Database.csproj.nuget.g.props"
    printf 'stray\n' > "${T}/src/Foo.Database/bin/Ignore.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
}

@test "a dacpac plus an F# test project is not treated as dacpac-only" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Database" "${T}/src/Foo.Database.Tests"
    printf '<Project Sdk="MSBuild.Sdk.SqlProj/2.5.0"></Project>\n' \
        > "${T}/src/Foo.Database/Foo.Database.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Database.Tests/Foo.Database.Tests.fsproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 1 ]
}

@test "a dacpac plus a VB test project is not treated as dacpac-only" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Database" "${T}/src/Foo.Database.Tests"
    printf '<Project Sdk="MSBuild.Sdk.SqlProj/2.5.0"></Project>\n' \
        > "${T}/src/Foo.Database/Foo.Database.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Database.Tests/Foo.Database.Tests.vbproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 1 ]
}

@test "a comment merely mentioning the SqlProj SDK does not cause a false positive" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Library"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <!-- migrated away from Sdk="MSBuild.Sdk.SqlProj/1.0.0" -->\n</Project>\n' \
        > "${T}/src/Foo.Library/Foo.Library.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 1 ]
}

@test "the element form of the SDK declaration is detected as a dacpac" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Database"
    printf '<Project>\n  <Sdk Name="MSBuild.Sdk.SqlProj" Version="2.5.0" />\n</Project>\n' \
        > "${T}/src/Foo.Database/Foo.Database.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
}
