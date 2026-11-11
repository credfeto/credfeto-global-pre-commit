#!/usr/bin/env bats
# Acceptance tests for src/scripts/check-benchmark-project-names, the guard
# that fails when a project containing BenchmarkDotNet benchmarks is not
# named <Name>.Benchmark.Tests (or does not use that namespace), since
# buildtest only keeps *.Benchmark.Tests out of its main test run.
# - detection is by a benchmark runner call in source (Benchmark<T>() or
#   BenchmarkRunner.Run), so a project that only gets BenchmarkDotNet
#   transitively is still found, while BenchmarkDotNet text in string
#   literals (analyzer tests) or a lone [Benchmark] class is not
# - the project file name, every namespace declaration in the project's own
#   files and an explicit RootNamespace are checked
# - bin/ and obj/, untracked files and projects with no benchmarks are ignored
# - the hook runs it on .NET changes and blocks the commit

load test_helper

CHECK="${REPO_DIR}/src/scripts/check-benchmark-project-names"

# Creates a repo with hooks disabled (this suite calls the script directly,
# apart from the one hook test) and prints its path.
make_names_repo() {
    local _t
    _t="$(make_repo feature/bench-names)"
    mkdir -p "${_t}/.no-hooks"
    git -C "${_t}" config core.hooksPath "${_t}/.no-hooks"
    printf '%s' "${_t}"
}

# write_project <repo> <dir relative to repo> <project name> [<RootNamespace>]
# Writes a project file with no BenchmarkDotNet PackageReference: like the
# real benchmark projects, it gets the package transitively (here through a
# FunFair.Test.Common reference).
write_project() {
    local _repo="$1" _dir="$2" _name="$3" _root_ns="${4:-}"
    mkdir -p "${_repo}/${_dir}"
    {
        printf '<Project Sdk="Microsoft.NET.Sdk">\n'
        if [ -n "${_root_ns}" ]; then
            printf '  <PropertyGroup>\n    <RootNamespace>%s</RootNamespace>\n  </PropertyGroup>\n' "${_root_ns}"
        fi
        printf '  <ItemGroup>\n    <PackageReference Include="FunFair.Test.Common" Version="1.0.0" />\n  </ItemGroup>\n'
        printf '</Project>\n'
    } > "${_repo}/${_dir}/${_name}.csproj"
}

# write_bench_class <file> <namespace>: a class with a [Benchmark] method and
# a test that runs it through FunFair.Test.Common's Benchmark<T>() helper.
write_bench_class() {
    mkdir -p "$(dirname "$1")"
    printf 'using BenchmarkDotNet.Attributes;\n\nnamespace %s;\n\npublic sealed class SampleBench\n{\n    [Benchmark]\n    public void Run() { }\n}\n\npublic sealed class SampleBenchTests : LoggingTestBase\n{\n    public void Run_Benchmarks()\n    {\n        (Summary _, AccumulationLogger logger) = Benchmark<SampleBench>();\n    }\n}\n' "$2" > "$1"
}

# write_bench_test <file> <namespace>: a test that runs benchmarks through
# Benchmark<T>(), carrying no [Benchmark] attribute itself.
write_bench_test() {
    mkdir -p "$(dirname "$1")"
    printf 'using BenchmarkDotNet.Reports;\nusing FunFair.Test.Common;\n\nnamespace %s;\n\npublic sealed class SampleTests : LoggingTestBase\n{\n    public void Run_Benchmarks()\n    {\n        (Summary _, AccumulationLogger logger) = Benchmark<OtherBench>();\n    }\n}\n' "$2" > "$1"
}

# write_plain_class <file> <namespace>
write_plain_class() {
    mkdir -p "$(dirname "$1")"
    printf 'namespace %s;\n\npublic sealed class Plain\n{\n    private readonly int[] _values = new int[1];\n}\n' "$2" > "$1"
}

stage_all() {
    git -C "$1" add -A
}

run_check() {
    run bash -c 'cd "$1" && env PATH="$2" sh "$3"' _ "$1" "${TEST_PATH}" "${CHECK}"
}

# ── passing cases ─────────────────────────────────────────────────────────────

@test "a correctly named benchmark project with BenchmarkDotNet only transitive passes" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests
    write_bench_class "${T}/src/Foo.Benchmark.Tests/Bench/SampleBench.cs" Foo.Benchmark.Tests.Bench
    write_bench_test "${T}/src/Foo.Benchmark.Tests/SampleTests.cs" Foo.Benchmark.Tests
    grep -q 'FunFair.Test.Common' "${T}/src/Foo.Benchmark.Tests/Foo.Benchmark.Tests.csproj"
    run grep -q 'BenchmarkDotNet' "${T}/src/Foo.Benchmark.Tests/Foo.Benchmark.Tests.csproj"
    [ "${status}" -eq 1 ]
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "a correctly named project with a matching RootNamespace passes" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests Foo.Benchmark.Tests
    write_bench_class "${T}/src/Foo.Benchmark.Tests/SampleBench.cs" Foo.Benchmark.Tests
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "a RootNamespace that is an MSBuild property is not checked" {
    local T
    T="$(make_names_repo)"
    # shellcheck disable=SC2016 # literal MSBuild property
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests '$(MSBuildProjectName)'
    write_bench_class "${T}/src/Foo.Benchmark.Tests/SampleBench.cs" Foo.Benchmark.Tests
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "a repo with projects but no benchmarks passes" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo Foo
    write_plain_class "${T}/src/Foo/Plain.cs" Foo
    write_project "${T}" src/Foo.Tests Foo.Tests
    write_plain_class "${T}/src/Foo.Tests/PlainTests.cs" Foo.Tests
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "a repo with no .cs files passes" {
    local T
    T="$(make_names_repo)"
    printf 'hello\n' > "${T}/readme.txt"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "benchmark sources under bin or obj are ignored" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo Foo
    write_plain_class "${T}/src/Foo/Plain.cs" Foo
    write_bench_class "${T}/src/Foo/obj/Release/Generated.cs" Foo
    write_bench_class "${T}/src/Foo/bin/Release/Copied.cs" Foo
    git -C "${T}" add -A
    git -C "${T}" add -f -- src/Foo/obj/Release/Generated.cs src/Foo/bin/Release/Copied.cs
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "an untracked benchmark source is ignored" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo Foo
    write_plain_class "${T}/src/Foo/Plain.cs" Foo
    stage_all "${T}"
    write_bench_class "${T}/src/Foo/Untracked.cs" Foo
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "an attribute whose name merely starts with Benchmark is not a benchmark marker" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo Foo
    printf 'namespace Foo;\n\n[BenchmarkingHelper]\npublic sealed class Plain { }\n' > "${T}/src/Foo/Plain.cs"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "a correctly named benchmark project does not make a nested project's namespace fail" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests
    write_bench_class "${T}/src/Foo.Benchmark.Tests/SampleBench.cs" Foo.Benchmark.Tests
    write_project "${T}" src/Foo.Benchmark.Tests/Nested Nested
    write_plain_class "${T}/src/Foo.Benchmark.Tests/Nested/Plain.cs" Nested
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

# ── failing cases ─────────────────────────────────────────────────────────────

@test "src/Bench with namespace Bench and transitive BenchmarkDotNet fails, naming the project" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Bench Bench
    write_bench_class "${T}/src/Bench/Benchmarks/RegexBench.cs" Bench.Benchmarks
    write_bench_test "${T}/src/Bench/RegexTests.cs" Bench
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Bench/Bench.csproj: project name Bench is not <Name>.Benchmark.Tests'* ]]
    [[ "${output}" == *'src/Bench/RegexTests.cs:4: namespace Bench is not'* ]]
    [[ "${output}" == *'src/Bench/Benchmarks/RegexBench.cs:3: namespace Bench.Benchmarks is not'* ]]
    [[ "${output}" == *'rename each project above, and its namespace, to <Name>.Benchmark.Tests'* ]]
}

@test "non-standard benchmark project names fail: BenchMark, Bench, singular, plural, lower-case, no prefix" {
    local T _name
    for _name in \
        Foo.BenchMark.Tests \
        Foo.Bench.Tests \
        Foo.Benchmark.Test \
        Foo.Benchmarks.Tests \
        Foo.benchmark.tests \
        Benchmark.Tests; do
        rm -rf "${BATS_TEST_TMPDIR}/repo"
        T="$(make_names_repo)"
        write_project "${T}" "src/${_name}" "${_name}"
        write_bench_class "${T}/src/${_name}/SampleBench.cs" Foo.Benchmark.Tests
        stage_all "${T}"
        run_check "${T}"
        [ "${status}" -ne 0 ] || fail_with_run_output "${status}" "${output}" "non-zero for ${_name}"
        [[ "${output}" == *"src/${_name}/${_name}.csproj: project name ${_name} is not"* ]] \
            || fail_with_run_output "${status}" "${output}" "a message naming ${_name}"
    done
}

@test "a project detected through a Benchmark<T>() runner call fails" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Perf Foo.Perf
    write_bench_test "${T}/src/Foo.Perf/SampleTests.cs" Foo.Perf
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Foo.Perf/Foo.Perf.csproj: project name Foo.Perf is not'* ]]
}

@test "BenchmarkDotNet using directives alone do not mark a benchmark project" {
    local T _directive
    for _directive in 'global using BenchmarkDotNet.Attributes;' 'using static BenchmarkDotNet.Running.BenchmarkRunner;'; do
        rm -rf "${BATS_TEST_TMPDIR}/repo"
        T="$(make_names_repo)"
        write_project "${T}" src/Foo.Perf Foo.Perf
        printf '%s\n' "${_directive}" > "${T}/src/Foo.Perf/Usings.cs"
        stage_all "${T}"
        run_check "${T}"
        [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" "zero for '${_directive}'"
    done
}

@test "a [Benchmark] attribute alone does not mark a benchmark project" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Perf Foo.Perf
    printf 'namespace Foo.Perf;\n\npublic sealed class SampleBench\n{\n    [Benchmark(Baseline = true)]\n    public void Run() { }\n}\n' \
        > "${T}/src/Foo.Perf/SampleBench.cs"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "BenchmarkDotNet text inside string literals (analyzer tests) is not a benchmark marker" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.CodeAnalysis.Tests Foo.CodeAnalysis.Tests
    printf 'namespace Foo.CodeAnalysis.Tests;\n\npublic sealed class AnalyzerTests\n{\n    private const string Source = @"\nusing BenchmarkDotNet.Attributes;\n\npublic sealed class X\n{\n    [Benchmark]\n    public void Run() { }\n}";\n}\n' \
        > "${T}/src/Foo.CodeAnalysis.Tests/AnalyzerTests.cs"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "the Benchmark<T>() helper's own declaration is not a runner call" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Test.Common Foo.Test.Common
    printf 'namespace Foo.Test.Common;\n\npublic abstract class LoggingTestBase\n{\n    protected static (Summary summary, AccumulationLogger logger) Benchmark<TBenchmark>()\n    {\n        return default;\n    }\n}\n' \
        > "${T}/src/Foo.Test.Common/LoggingTestBase.cs"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -eq 0 ]
}

@test "a misnamed project calling BenchmarkRunner.Run fails" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Perf Foo.Perf
    printf 'namespace Foo.Perf;\n\npublic static class Program\n{\n    public static void Main() => BenchmarkRunner.Run<Program>();\n}\n' \
        > "${T}/src/Foo.Perf/Program.cs"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Foo.Perf/Foo.Perf.csproj: project name Foo.Perf is not'* ]]
}

@test "a correctly named project with a namespace outside *.Benchmark.Tests fails" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests
    write_bench_class "${T}/src/Foo.Benchmark.Tests/SampleBench.cs" Foo.Benchmark.Tests
    write_plain_class "${T}/src/Foo.Benchmark.Tests/Helpers/Helper.cs" Foo.Benchmarks
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Foo.Benchmark.Tests/Helpers/Helper.cs:1: namespace Foo.Benchmarks is not'* ]]
    [[ "${output}" != *': project name '* ]]
}

@test "a correctly named project with a block-scoped wrong namespace fails" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests
    printf 'using BenchmarkDotNet.Attributes;\n\nnamespace Foo.BenchMark.Tests\n{\n    public sealed class SampleBench { [Benchmark] public void Run() { } }\n    public sealed class SampleBenchTests { public void Run() { _ = Benchmark<SampleBench>(); } }\n}\n' \
        > "${T}/src/Foo.Benchmark.Tests/SampleBench.cs"
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'SampleBench.cs:3: namespace Foo.BenchMark.Tests is not'* ]]
}

@test "a correctly named project with a RootNamespace outside *.Benchmark.Tests fails" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Foo.Benchmark.Tests Foo.Benchmark.Tests Bench
    write_bench_class "${T}/src/Foo.Benchmark.Tests/SampleBench.cs" Foo.Benchmark.Tests
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Foo.Benchmark.Tests/Foo.Benchmark.Tests.csproj: RootNamespace Bench is not'* ]]
}

@test "an already committed misnamed project fails even when the staged change is elsewhere" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Bench Bench
    write_bench_class "${T}/src/Bench/SampleBench.cs" Bench
    write_project "${T}" src/Foo Foo
    write_plain_class "${T}/src/Foo/Plain.cs" Foo
    stage_all "${T}"
    git -C "${T}" commit --quiet -m baseline
    printf '// touch\n' >> "${T}/src/Foo/Plain.cs"
    git -C "${T}" add src/Foo/Plain.cs
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Bench/Bench.csproj: project name Bench is not'* ]]
}

@test "a benchmark source with a non-ASCII file name is detected" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" src/Bench Bench
    write_bench_class "${T}/src/Bench/Ünits.cs" Bench
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/Bench/Bench.csproj: project name Bench is not'* ]]
    [[ "${output}" == *'src/Bench/Ünits.cs:3: namespace Bench is not'* ]]
}

@test "a project directory with spaces in its path is reported" {
    local T
    T="$(make_names_repo)"
    write_project "${T}" "src/My Bench" Bench
    write_bench_class "${T}/src/My Bench/SampleBench.cs" Bench
    stage_all "${T}"
    run_check "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'src/My Bench/Bench.csproj: project name Bench is not'* ]]
}

# ── hook wiring ───────────────────────────────────────────────────────────────

@test "pre-commit blocks a commit of a misnamed benchmark project" {
    local T
    T="$(make_repo)"
    printf 'repos: []\n' > "${T}/.pre-commit-config.yaml"
    write_project "${T}" src/Bench Bench
    write_bench_class "${T}/src/Bench/SampleBench.cs" Bench
    git -C "${T}" add -A
    run_hook "${T}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *'checking benchmark project names'* ]]
    [[ "${output}" == *'src/Bench/Bench.csproj: project name Bench is not <Name>.Benchmark.Tests'* ]]
    [[ "${output}" == *'benchmark project naming'* ]]
}
