#!/usr/bin/env bats
# Acceptance tests for src/scripts/benchmark-test-affected, the pure git+file
# analysis helper buildtest uses to decide which benchmark test projects its
# separate, sequential-only benchmark test step should run. Invoked directly
# -- no dotnet required.

load test_helper

FILTER="${REPO_DIR}/src/scripts/benchmark-test-affected"

# Builds on the shared make_repo fixture, but overrides core.hooksPath to a
# no-op directory -- this suite exercises the helper script directly, never
# the real pre-commit hook, so the real hooks must not fire on our commits.
make_bench_repo() {
    local _t
    _t="$(make_repo feature/bench-test)"
    mkdir -p "${_t}/.no-hooks"
    git -C "${_t}" config core.hooksPath "${_t}/.no-hooks"
    printf '%s' "${_t}"
}

# Lays out a fixture solution under "$1/src":
#   Foo.Extensions                          -- leaf production project
#   Foo.DataTypes            -> Extensions   -- production project
#   Foo.DataTypes.Benchmark.Tests -> DataTypes
#   Foo.Metrics                             -- leaf production project
#   Foo.Metrics.Benchmark.Tests -> Metrics
#   Foo.Widgets                             -- leaf production project
#   Foo.Widgets.Benchmark.Tests -> Widgets
#   Foo.Metrics.Integration.Tests            -- no ProjectReference, unrelated fixture
write_fixture() {
    local _t="$1"
    mkdir -p \
        "${_t}/src/Foo.Extensions" \
        "${_t}/src/Foo.DataTypes" \
        "${_t}/src/Foo.DataTypes.Benchmark.Tests" \
        "${_t}/src/Foo.Metrics" \
        "${_t}/src/Foo.Metrics.Benchmark.Tests" \
        "${_t}/src/Foo.Widgets" \
        "${_t}/src/Foo.Widgets.Benchmark.Tests" \
        "${_t}/src/Foo.Metrics.Integration.Tests"

    printf '<Solution></Solution>\n' > "${_t}/src/Foo.slnx"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Extensions/Foo.Extensions.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.Extensions\\Foo.Extensions.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.DataTypes/Foo.DataTypes.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.DataTypes\\Foo.DataTypes.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.DataTypes.Benchmark.Tests/Foo.DataTypes.Benchmark.Tests.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Metrics/Foo.Metrics.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.Metrics\\Foo.Metrics.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Widgets/Foo.Widgets.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo.Widgets\\Foo.Widgets.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/Foo.Widgets.Benchmark.Tests/Foo.Widgets.Benchmark.Tests.csproj"

    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${_t}/src/Foo.Metrics.Integration.Tests/Foo.Metrics.Integration.Tests.csproj"
}

commit_baseline() {
    local _t="$1"
    git -C "${_t}" add -A
    git -C "${_t}" commit --quiet -m baseline
}

DATATYPES_BENCH_REL="Foo.DataTypes.Benchmark.Tests/Foo.DataTypes.Benchmark.Tests.csproj"
METRICS_BENCH_REL="Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"
WIDGETS_BENCH_REL="Foo.Widgets.Benchmark.Tests/Foo.Widgets.Benchmark.Tests.csproj"

# ── nothing staged ────────────────────────────────────────────────────────────

@test "nothing staged runs every benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${WIDGETS_BENCH_REL}"
}

# ── not a git repository ──────────────────────────────────────────────────────

@test "solution outside any git repository runs every benchmark" {
    local T="${BATS_TEST_TMPDIR}/standalone"
    write_fixture "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${WIDGETS_BENCH_REL}"
}

# ── own project changed ───────────────────────────────────────────────────────

@test "benchmark whose own project changed is affected; untouched siblings are not" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"
    git -C "${T}" add "src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    [[ "${output}" != *"${DATATYPES_BENCH_REL}"* ]]
    [[ "${output}" != *"${WIDGETS_BENCH_REL}"* ]]
}

# ── direct reference changed ──────────────────────────────────────────────────

@test "benchmark whose directly-referenced project changed is affected" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.DataTypes/Foo.DataTypes.csproj"
    git -C "${T}" add "src/Foo.DataTypes/Foo.DataTypes.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
}

# ── transitive reference changed ──────────────────────────────────────────────

@test "benchmark whose transitively-referenced project changed is affected; unrelated benchmarks are not" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    # Foo.DataTypes.Benchmark.Tests -> Foo.DataTypes -> Foo.Extensions
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Extensions/Foo.Extensions.csproj"
    git -C "${T}" add "src/Foo.Extensions/Foo.Extensions.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    [[ "${output}" != *"${METRICS_BENCH_REL}"* ]]
    [[ "${output}" != *"${WIDGETS_BENCH_REL}"* ]]
}

# ── shared build file changed ─────────────────────────────────────────────────

@test "solution-level shared build file change affects every benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.slnx"
    git -C "${T}" add "src/Foo.slnx"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${WIDGETS_BENCH_REL}"
}

@test "Directory.Build.props change affects every benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    printf '<Project></Project>\n' > "${T}/src/Directory.Build.props"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Directory.Build.props"
    git -C "${T}" add "src/Directory.Build.props"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${WIDGETS_BENCH_REL}"
}

# ── non-code file ──────────────────────────────────────────────────────────────

@test "non-code file change inside a project directory does not count as affecting it, so all run" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf 'notes\n' > "${T}/src/Foo.Metrics/README.md"
    git -C "${T}" add "src/Foo.Metrics/README.md"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    # Not .NET-relevant, so nothing is considered changed -- same as nothing staged: run everything.
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
}

# ── false-positive naming ─────────────────────────────────────────────────────

@test "a test project whose name merely contains bench as a substring is never printed" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    mkdir -p "${T}/src/Foo.Workbench.Tests"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' \
        > "${T}/src/Foo.Workbench.Tests/Foo.Workbench.Tests.csproj"
    commit_baseline "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *'Foo.Workbench.Tests'* ]]
}

# ── only *.Benchmark.Tests is a benchmark project ─────────────────────────────

# *.Benchmark.Tests, case-sensitive and with a name before it, is the only
# accepted benchmark project name (issue #294). The old variants, and the
# plural Benchmarks.Tests, are ordinary test projects to this helper.
@test "only *.Benchmark.Tests is a benchmark project; BenchMark, Bench, singular, plural and lower-case variants are not" {
    local T _name
    T="$(make_bench_repo)"
    write_fixture "${T}"
    for _name in \
        Foo.Gadgets.BenchMark.Tests \
        Foo.Gadgets.Bench.Tests \
        Foo.Gadgets.Benchmark.Test \
        Foo.Gadgets.Benchmarks.Tests \
        Foo.Gadgets.benchmark.tests \
        Foo.Gadgets.BENCHMARK.TESTS \
        Benchmark.Tests; do
        mkdir -p "${T}/src/${_name}"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${T}/src/${_name}/${_name}.csproj"
    done
    commit_baseline "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${WIDGETS_BENCH_REL}"
    [[ "${output}" != *'Gadgets'* ]]
}

@test "a solution whose only test project uses a non-standard benchmark name prints nothing" {
    local T
    T="$(make_bench_repo)"
    mkdir -p "${T}/src/Foo" "${T}/src/Foo.BenchMark.Tests"
    printf '<Solution></Solution>\n' > "${T}/src/Foo.slnx"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${T}/src/Foo/Foo.csproj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${T}/src/Foo.BenchMark.Tests/Foo.BenchMark.Tests.csproj"
    commit_baseline "${T}"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

# ── ProjectReference with a preceding attribute ───────────────────────────────

@test "a ProjectReference with a Condition attribute before Include is still followed" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    cat > "${T}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj" <<'CSPROJ_EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Condition="'$(TargetFramework)'=='net9.0'" Include="..\Foo.Metrics\Foo.Metrics.csproj" />
  </ItemGroup>
</Project>
CSPROJ_EOF
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Metrics/Foo.Metrics.csproj"
    git -C "${T}" add "src/Foo.Metrics/Foo.Metrics.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
}

# ── unresolvable ProjectReference ──────────────────────────────────────────────

@test "an unresolvable ProjectReference (MSBuild property) makes every benchmark run" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    # shellcheck disable=SC2016
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="$(SolutionDir)Foo.Metrics\\Foo.Metrics.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${T}/src/Foo.Metrics.Benchmark.Tests/Foo.Metrics.Benchmark.Tests.csproj"
    commit_baseline "${T}"
    printf '<!-- touch -->\n' >> "${T}/src/Foo.Widgets/Foo.Widgets.csproj"
    git -C "${T}" add "src/Foo.Widgets/Foo.Widgets.csproj"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    printf '%s\n' "${lines[@]}" | grep -qxF "${DATATYPES_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${METRICS_BENCH_REL}"
    printf '%s\n' "${lines[@]}" | grep -qxF "${WIDGETS_BENCH_REL}"
}

# ── non-ASCII file name ───────────────────────────────────────────────────────

# git C-quotes a non-ASCII name in line-separated output (Ünits.cs comes out
# as "...\303\234nits.cs", quotes included), which no longer ends in .cs, so
# the change would be missed and every benchmark would run instead of only
# the affected one.
@test "a staged source file with a non-ASCII name affects only its own project's benchmark" {
    local T
    T="$(make_bench_repo)"
    write_fixture "${T}"
    commit_baseline "${T}"
    printf 'class Units {}\n' > "${T}/src/Foo.Metrics/Ünits.cs"
    git -C "${T}" add -- "src/Foo.Metrics/Ünits.cs"
    run "${FILTER}" "${T}/src"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${METRICS_BENCH_REL}" ]
}
