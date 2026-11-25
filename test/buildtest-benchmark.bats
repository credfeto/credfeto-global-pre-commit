#!/usr/bin/env bats
# Acceptance tests for src/scripts/buildtest's separate benchmark test step:
# a human's commit runs the benchmark projects its staged changes affect, an
# AI agent's commit (CLAUDECODE=1) skips the step and leaves the benchmarks
# to CI.
#
# A stubbed `dotnet` on PATH logs every call and reports a stable SDK, so the
# pre-release SDK skip does not apply and no real SDK is required.

load test_helper

bats_require_minimum_version 1.5.0

BUILDTEST="${REPO_DIR}/src/scripts/buildtest"
BENCH_REL="Foo.Benchmark.Tests/Foo.Benchmark.Tests.csproj"

# make_dotnet_stub <bin dir> <call log>
# Writes a `dotnet` that appends its arguments to <call log>, prints a stable
# SDK version, lists cscleanup as an installed tool and otherwise succeeds.
make_dotnet_stub() {
    mkdir -p "$1"
    cat > "$1/dotnet" << STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$2"
case "\$1" in
    --version) printf '10.0.100\n' ;;
    tool)
        printf 'Package Id                        Version      Commands\n'
        printf 'credfeto.dotnet.repo.formatter    1.0.0        cscleanup\n'
        ;;
esac
exit 0
STUB
    chmod +x "$1/dotnet"
}

# setup_bench_repo
# Creates a repo whose solution has a production project and a benchmark
# project referencing it, committed, with a change to the production project
# staged so the benchmark project is affected. Prints the repo path.
setup_bench_repo() {
    local _t
    _t="$(make_repo feature/buildtest-benchmark)"
    mkdir -p "${_t}/src/Foo" "${_t}/src/Foo.Benchmark.Tests"
    printf '<Solution></Solution>\n' > "${_t}/src/Foo.slnx"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${_t}/src/Foo/Foo.csproj"
    printf 'class Foo { }\n' > "${_t}/src/Foo/Foo.cs"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <ProjectReference Include="..\\Foo\\Foo.csproj" />\n  </ItemGroup>\n</Project>\n' \
        > "${_t}/src/${BENCH_REL}"
    commit_without_hooks "${_t}" src
    printf 'class Foo { int Bar; }\n' > "${_t}/src/Foo/Foo.cs"
    git -C "${_t}" add src/Foo/Foo.cs
    make_dotnet_stub "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/dotnet.log"
    mkdir -p "${BATS_TEST_TMPDIR}/tmp"
    printf '%s' "${_t}"
}

# run_buildtest <repo> [NAME=value ...]
# Runs buildtest from <repo> with the stub dotnet first on PATH, TMPDIR in
# the test's own directory and CLAUDECODE unset unless given.
run_buildtest() {
    local _repo="$1"
    shift
    cd "${_repo}" || return 1
    run env -u CLAUDECODE PATH="${BATS_TEST_TMPDIR}/bin:${TEST_PATH}" \
        TMPDIR="${BATS_TEST_TMPDIR}/tmp" "$@" sh "${BUILDTEST}"
}

@test "a human's commit runs the benchmark project its staged changes affect" {
    local T
    T="$(setup_bench_repo)"

    run_buildtest "${T}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Running benchmark tests: ${BENCH_REL}"* ]]
    [[ "${output}" != *"skipping benchmark tests"* ]]
    grep -q "^test ${BENCH_REL} " "${BATS_TEST_TMPDIR}/dotnet.log"
}

@test "an AI agent's commit skips the benchmark tests and leaves them to CI" {
    local T
    T="$(setup_bench_repo)"

    run_buildtest "${T}" CLAUDECODE=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"AI agent commit, skipping benchmark tests (CI runs them)"* ]]
    [[ "${output}" != *"Determining which benchmarks are affected"* ]]
    [[ "${output}" != *"Running benchmark tests"* ]]
    [ "$(grep -c "^test ${BENCH_REL}" "${BATS_TEST_TMPDIR}/dotnet.log")" -eq 0 ]
    # The main test run, with the benchmarks filtered out, still runs.
    grep -q '^test .*--filter-not-namespace \*\.Benchmark\.Tests ' "${BATS_TEST_TMPDIR}/dotnet.log"
}

@test "CLAUDECODE set to anything other than 1 is not an AI agent, so the benchmarks run" {
    local T
    T="$(setup_bench_repo)"

    run_buildtest "${T}" CLAUDECODE=0

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" != *"AI agent commit"* ]]
    grep -q "^test ${BENCH_REL} " "${BATS_TEST_TMPDIR}/dotnet.log"
}
