#!/usr/bin/env bats
# Acceptance tests for src/scripts/benchmark-test-exclude, the pure
# file-analysis helper buildtest's main `dotnet test` step uses to
# unconditionally exclude every benchmark test project (run separately, see
# benchmark-test-affected) plus the always-safe integration test exclude.
# Invoked directly -- no dotnet, and no git changes, required.

load test_helper

SCRIPT="${REPO_DIR}/src/scripts/benchmark-test-exclude"

@test "integration excludes are always present" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Library"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Library/Foo.Library.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'*.Integration.Tests'* ]]
    [[ "${output}" == *'*.Integration.Tests.*'* ]]
}

@test "no benchmark projects prints only the integration excludes" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Library"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Library/Foo.Library.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "every benchmark naming variant is excluded unconditionally" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p \
        "${T}/src/Foo.DataTypes.BenchMark.Tests" \
        "${T}/src/Foo.Metrics.Benchmark.Tests" \
        "${T}/src/Foo.Widgets.BenchMark.Test"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.DataTypes.BenchMark.Tests/Foo.DataTypes.BenchMark.Tests.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Widgets.BenchMark.Test/Foo.Widgets.BenchMark.Test.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'*.Foo.DataTypes.BenchMark.Tests'* ]]
    [[ "${output}" == *'*.Foo.Metrics.Benchmark.Tests'* ]]
    [[ "${output}" == *'*.Foo.Widgets.BenchMark.Test'* ]]
}

@test "a test project whose name merely contains bench as a substring is not excluded" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Workbench.Tests"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Workbench.Tests/Foo.Workbench.Tests.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Foo.Workbench.Tests'* ]]
}

@test "generated .csproj-like files under obj/bin are ignored" {
    local T="${BATS_TEST_TMPDIR}/solution"
    mkdir -p "${T}/src/Foo.Metrics.Benchmark.Tests/obj" "${T}/src/Foo.Metrics.Benchmark.Tests/bin"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"
    printf 'stray\n' > "${T}/src/Foo.Metrics.Benchmark.Tests/obj/Stray.Benchmark.Tests.csproj"
    printf 'stray\n' > "${T}/src/Foo.Metrics.Benchmark.Tests/bin/Stray.Benchmark.Tests.csproj"
    run "${SCRIPT}" "${T}"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF '*.Foo.Metrics.Benchmark.Tests'
    [[ "${output}" != *'Stray'* ]]
}
