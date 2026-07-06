#!/usr/bin/env bats
# Acceptance tests for src/scripts/benchmark-test-filter, the pure git+file
# analysis helper buildtest uses to decide which benchmark test projects the
# staged change set cannot affect (and therefore skips), plus the always-safe
# integration test exclude.  Invoked directly — no dotnet required.

load test_helper

FILTER="${REPO_DIR}/src/scripts/benchmark-test-filter"

# Creates an isolated git repository with hooks disabled (this suite exercises
# the helper script directly, not the pre-commit hook) and prints its path.
make_bench_repo() {
    local _t="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${_t}/.no-hooks"
    git -C "${_t}" init --quiet
    git -C "${_t}" symbolic-ref HEAD "refs/heads/feature/bench-test"
    git -C "${_t}" config user.email "test@example.com"
    git -C "${_t}" config user.name "Test User"
    git -C "${_t}" config core.hooksPath "${_t}/.no-hooks"
    printf '%s' "${_t}"
}

# Lays out a fixture solution under "$1/src":
#   Foo.Extensions                          — leaf production project
#   Foo.DataTypes            -> Extensions   — production project
#   Foo.DataTypes.BenchMark.Tests -> DataTypes  (mixed-case "BenchMark.Tests" variant)
#   Foo.Metrics                             — leaf production project
#   Foo.Metrics.Benchmark.Tests -> Metrics      (standard "Benchmark.Tests" variant)
#   Foo.Widgets                             — leaf production project
#   Foo.Widgets.BenchMark.Test -> Widgets       (singular "BenchMark.Test" variant)
#   Foo.Metrics.Integration.Tests            — no ProjectReference, proves integration exclude
write_fixture() {
    local _t="$1"
    mkdir -p \
        "${_t}/src/Foo.Extensions" \
        "${_t}/src/Foo.DataTypes" \
        "${_t}/src/Foo.DataTypes.BenchMark.Tests" \
        "${_t}/src/Foo.Metrics" \
        "${_t}/src/Foo.Metrics.Benchmark.Tests" \
        "${_t}/src/Foo.Widgets" \
        "${_t}/src/Foo.Widgets.BenchMark.Test" \
        "${_t}/src/Foo.Metrics.Integration.Tests"

    printf '<Solution></Solution>\n' > "${_t}/src/Foo.slnx"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Extensions/Foo.Extensions.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.Extensions\\Foo.Extensions.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.DataTypes/Foo.DataTypes.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.DataTypes\\Foo.DataTypes.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.DataTypes.BenchMark.Tests/Foo.DataTypes.BenchMark.Tests.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Metrics/Foo.Metrics.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.Metrics\\Foo.Metrics.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Widgets/Foo.Widgets.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.Widgets\\Foo.Widgets.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.Widgets.BenchMark.Test/Foo.Widgets.BenchMark.Test.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Metrics.Integration.Tests/Foo.Metrics.Integration.Tests.csproj"
}

commit_baseline() {
    local _t="$1"
    git -C "${_t}" add -A
    git -C "${_t}" commit --quiet -m baseline
}

# ── integration tests always excluded ─────────────────────────────────────────

@test "integration excludes are always present, even with nothing staged" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'*.Integration.Tests'* ]]
    [[ "${output}" == *'*.Integration.Tests.*'* ]]
}

# ── nothing staged ────────────────────────────────────────────────────────────

@test "nothing staged runs every benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Benchmark'* ]]
    [[ "${output}" != *'BenchMark'* ]]
}

# ── own project changed ───────────────────────────────────────────────────────

@test "benchmark whose own project changed is not excluded" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Metrics/Foo.Metrics.csproj"
    git -C "${T}" add "src/Foo.Metrics/Foo.Metrics.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Foo.Metrics.Benchmark.Tests'* ]]
    [[ "${output}" == *'*.Foo.DataTypes.BenchMark.Tests'* ]]
}

# ── direct reference changed ──────────────────────────────────────────────────

@test "benchmark whose directly-referenced project changed is not excluded" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.DataTypes/Foo.DataTypes.csproj"
    git -C "${T}" add "src/Foo.DataTypes/Foo.DataTypes.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Foo.DataTypes.BenchMark.Tests'* ]]
}

# ── transitive reference changed ──────────────────────────────────────────────

@test "benchmark whose transitively-referenced project changed is not excluded" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    # Foo.DataTypes.BenchMark.Tests -> Foo.DataTypes -> Foo.Extensions
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Extensions/Foo.Extensions.csproj"
    git -C "${T}" add "src/Foo.Extensions/Foo.Extensions.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Foo.DataTypes.BenchMark.Tests'* ]]
    # Unrelated benchmarks are still unaffected and excluded.
    [[ "${output}" == *'*.Foo.Metrics.Benchmark.Tests'* ]]
    [[ "${output}" == *'*.Foo.Widgets.BenchMark.Test'* ]]
}

# ── untouched benchmark closure ───────────────────────────────────────────────

@test "benchmark with an untouched closure is excluded as namespace and wildcard" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Metrics/Foo.Metrics.csproj"
    git -C "${T}" add "src/Foo.Metrics/Foo.Metrics.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF '*.Foo.DataTypes.BenchMark.Tests'
    printf '%s\n' "${lines[@]}" | grep -qxF '*.Foo.DataTypes.BenchMark.Tests.*'
}

# ── shared build file changed ─────────────────────────────────────────────────

@test "solution-level shared build file change excludes no benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.slnx"
    git -C "${T}" add "src/Foo.slnx"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Benchmark'* ]]
    [[ "${output}" != *'BenchMark'* ]]
}

@test "Directory.Build.props change excludes no benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    printf '<Project></Project>\n' > "${T}/src/Directory.Build.props"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Directory.Build.props"
    git -C "${T}" add "src/Directory.Build.props"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Benchmark'* ]]
    [[ "${output}" != *'BenchMark'* ]]
}

# ── non-code file ──────────────────────────────────────────────────────────────

@test "non-code file change inside a project directory does not count as affecting it" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf 'notes\n' > "${T}/src/Foo.Metrics/README.md"
    git -C "${T}" add "src/Foo.Metrics/README.md"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    # Not .NET-relevant, so nothing is considered changed — same as nothing staged: run everything.
    [[ "${output}" != *'Benchmark'* ]]
    [[ "${output}" != *'BenchMark'* ]]
}

# ── naming variants ────────────────────────────────────────────────────────────

@test "all benchmark naming variants are detected" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    # A staged change unrelated to any benchmark's closure forces all three to be
    # judged unaffected, proving each naming variant is actually found and excluded.
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Metrics.Integration.Tests/Foo.Metrics.Integration.Tests.csproj"
    git -C "${T}" add "src/Foo.Metrics.Integration.Tests/Foo.Metrics.Integration.Tests.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'*.Foo.DataTypes.BenchMark.Tests'* ]]
    [[ "${output}" == *'*.Foo.Metrics.Benchmark.Tests'* ]]
    [[ "${output}" == *'*.Foo.Widgets.BenchMark.Test'* ]]
}
