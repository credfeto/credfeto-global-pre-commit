#!/usr/bin/env bats
# Acceptance tests for the warning-only slow tests and slow build parts
# reports: src/scripts/lib/slow-report.sh on fixture TRX, JUnit and MSBuild
# log files, how src/scripts/buildtest collects and prints them (with its
# per-step timings line), and how src/scripts/run-bats prints the slowest
# bats tests. Nothing in these reports may fail a commit.
#
# The buildtest tests use a stubbed `dotnet` on PATH, so no real SDK is
# required: its `build` writes a fixture MSBuild log to the -flp logfile and
# its `test` writes a fixture TRX file into the --results-directory.

load test_helper

bats_require_minimum_version 1.5.0

BUILDTEST="${REPO_DIR}/src/scripts/buildtest"
RUN_BATS="${REPO_DIR}/src/scripts/run-bats"
LIB="${REPO_DIR}/src/scripts/lib/slow-report.sh"
# By full path, so a test can give the report a PATH without python3.
SH="$(type -P sh)"

# write_trx <file> <test name>=<TRX duration>...
# Writes a TRX file holding one passed UnitTestResult per pair, in the shape
# xunit v3's --report-xunit-trx writes.
write_trx() {
    local _file="$1" _pair
    shift
    mkdir -p "$(dirname "${_file}")"
    {
        printf '<?xml version="1.0" encoding="utf-8"?>\n'
        printf '<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>\n'
        for _pair in "$@"; do
            printf '<UnitTestResult testName="%s" outcome="Passed" duration="%s" />\n' "${_pair%%=*}" "${_pair#*=}"
        done
        printf '</Results></TestRun>\n'
    } > "${_file}"
}

# write_build_log <file>
# Writes a trimmed detailed MSBuild file log, built with
# -p:ReportAnalyzer=true and PerformanceSummary, of a 60 second build: two
# compiles' analyzer and generator reports, then the performance summaries.
write_build_log() {
    cat > "$1" << 'LOG'
Build started 11/13/2026 16:03:04.
     1>Project "/src/App.Tests/App.Tests.csproj" on node 1 (default targets).
       Task "Csc"
         NOTE: Elapsed time may be less than analyzer execution time because analyzers can run concurrently.
         Total analyzer execution time: 12.500 seconds.
         Time (s)    %   Analyzer
         12.000   96   SlowAnalyzer, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
         11.000   88      SlowAnalyzer.Rules.Expensive (SA0001)
         <0.001   <1   TinyAnalyzer, Version=2.0.0.0, Culture=neutral, PublicKeyToken=null
         Total generator execution time: 0.900 seconds.
         Time (s)    %   Generator
         0.800   88   EnumGenerator.Package, Version=1.2.0.0, Culture=neutral, PublicKeyToken=null
         0.800   88      EnumGenerator.Package.EnumGenerator
       Done executing task "Csc".
   2:2>Task "Csc"
         Total analyzer execution time: 3.000 seconds.
         Time (s)    %   Analyzer
         3.000  100   SlowAnalyzer, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
       Done executing task "Csc".

Project Evaluation Performance Summary:
      170 ms  /src/App/App.csproj   1 calls

Project Performance Summary:
    40000 ms  /src/App.Tests/App.Tests.csproj   1 calls
    10943 ms  /src/App/App.csproj   5 calls
                 35 ms  GetTargetFrameworks                        1 calls

Target Performance Summary:
        2 ms  GetAssemblyVersion                         2 calls
     9000 ms  _CopyFilesMarkedCopyLocal                  1 calls
    16520 ms  CoreCompile                                2 calls
    35000 ms  ResolveProjectReferences                   2 calls

Task Performance Summary:
    16519 ms  Csc                                        2 calls
    11140 ms  MSBuild                                    6 calls

Build succeeded.
    0 Warning(s)
    0 Error(s)

Time Elapsed 00:01:00.00
LOG
}

# run_report <function> <argument> [NAME=value ...]
# Runs the slow-report.sh function <function> <argument> with none of the
# SLOW_* settings inherited, plus any NAME=value assignments given.
run_report() {
    local _function="$1" _argument="$2"
    shift 2
    # shellcheck disable=SC2016 # intentionally literal, expanded by the inner sh, not here
    run env -u SLOW_TEST_THRESHOLD_SECONDS -u SLOW_TEST_TOP -u SLOW_BUILD_SHARE_PERCENT \
        -u SLOW_BUILD_THRESHOLD_SECONDS "$@" "${SH}" -c '. "$1"; "$2" "$3"' _ "${LIB}" "${_function}" "${_argument}"
}

# Counts the lines of $output that list a test: two leading spaces, then
# seconds, then the name.
count_listed() {
    printf '%s\n' "${output}" | grep -cE '^ +[0-9]+\.[0-9]{2}s  '
}

# ── slowest tests (TRX) ───────────────────────────────────────────────────────

@test "slowest tests lists the top 10 by duration, slowest first, with no warning under the threshold" {
    local _dir="${BATS_TEST_TMPDIR}/results" _pairs=() _i
    for _i in 01 02 03 04 05 06 07 08 09 10 11 12; do
        _pairs+=("Tests.T${_i}=00:00:01.${_i}00000")
    done
    write_trx "${_dir}/a.trx" "${_pairs[@]}"

    run_report report_slow_tests_trx "${_dir}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests (top 10 of 12, warning above 2s):"* ]]
    [ "$(count_listed)" -eq 10 ]
    [ "$(printf '%s\n' "${output}" | grep -E '^ +[0-9]' | head -1)" = "       1.12s  Tests.T12" ]
    [[ "${output}" != *"Tests.T02"* ]]
    [[ "${output}" != *"WARNING"* ]]
}

@test "slowest tests warns on each test over SLOW_TEST_THRESHOLD_SECONDS, but not one exactly at it" {
    local _dir="${BATS_TEST_TMPDIR}/results"
    write_trx "${_dir}/a.trx" "Tests.AtLimit=00:00:02.0000000" "Tests.Slow=00:00:03.5000000" \
        "Tests.Slower=00:01:05.2500000" "Tests.Fast=00:00:00.0100000"

    run_report report_slow_tests_trx "${_dir}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(printf '%s\n' "${output}" | grep '^WARNING')" = "WARNING: slow test Tests.Slower 65.25s
WARNING: slow test Tests.Slow 3.50s" ]
}

@test "SLOW_TEST_TOP and SLOW_TEST_THRESHOLD_SECONDS change the slowest tests report" {
    local _dir="${BATS_TEST_TMPDIR}/results"
    write_trx "${_dir}/a.trx" "Tests.A=00:00:00.6000000" "Tests.B=00:00:00.7000000" "Tests.C=00:00:00.1000000"

    run_report report_slow_tests_trx "${_dir}" SLOW_TEST_TOP=2 SLOW_TEST_THRESHOLD_SECONDS=0.5

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests (top 2 of 3, warning above 0.5s):"* ]]
    [ "$(count_listed)" -eq 2 ]
    [[ "${output}" == *"WARNING: slow test Tests.B 0.70s"* ]]
    [[ "${output}" == *"WARNING: slow test Tests.A 0.60s"* ]]
    [[ "${output}" != *"WARNING: slow test Tests.C"* ]]
}

@test "SLOW_TEST_TOP=0 lists no tests but still warns on slow ones" {
    local _dir="${BATS_TEST_TMPDIR}/results"
    write_trx "${_dir}/a.trx" "Tests.Slow=00:00:03.0000000"

    run_report report_slow_tests_trx "${_dir}" SLOW_TEST_TOP=0

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(count_listed)" -eq 0 ]
    [[ "${output}" == *"WARNING: slow test Tests.Slow 3.00s"* ]]
}

@test "invalid slow test settings fall back to their defaults with a warning" {
    local _dir="${BATS_TEST_TMPDIR}/results"
    write_trx "${_dir}/a.trx" "Tests.Slow=00:00:03.0000000" "Tests.Fast=00:00:01.0000000"

    run_report report_slow_tests_trx "${_dir}" SLOW_TEST_TOP=lots SLOW_TEST_THRESHOLD_SECONDS=-1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"WARNING: SLOW_TEST_TOP=lots is not a non-negative number, using 10"* ]]
    [[ "${output}" == *"WARNING: SLOW_TEST_THRESHOLD_SECONDS=-1 is not a non-negative number, using 2"* ]]
    [[ "${output}" == *"Slowest tests (top 2 of 2, warning above 2s):"* ]]
    [[ "${output}" == *"WARNING: slow test Tests.Slow 3.00s"* ]]
}

@test "slowest tests combines the TRX files of every test project under the directory" {
    local _dir="${BATS_TEST_TMPDIR}/results"
    write_trx "${_dir}/one.trx" "One.Tests.A=00:00:00.2000000"
    write_trx "${_dir}/nested/two.trx" "Two.Tests.B=00:00:00.3000000"

    run_report report_slow_tests_trx "${_dir}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests (top 2 of 2, "* ]]
    [[ "${output}" == *"0.30s  Two.Tests.B"* ]]
    [[ "${output}" == *"0.20s  One.Tests.A"* ]]
}

@test "slowest tests with no TRX file says so and succeeds" {
    mkdir -p "${BATS_TEST_TMPDIR}/results"

    run_report report_slow_tests_trx "${BATS_TEST_TMPDIR}/results"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests: no test results found"* ]]

    run_report report_slow_tests_trx "${BATS_TEST_TMPDIR}/missing"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests: no test results found"* ]]
}

@test "a malformed TRX file is warned about and skipped, and the others are still reported" {
    local _dir="${BATS_TEST_TMPDIR}/results"
    mkdir -p "${_dir}"
    printf '<TestRun><Results><UnitTestResult testName="Broken"' > "${_dir}/broken.trx"
    write_trx "${_dir}/good.trx" "Tests.Good=00:00:00.5000000" "Tests.NoDuration=" "Tests.BadDuration=soon"

    run_report report_slow_tests_trx "${_dir}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"WARNING: could not read test results broken.trx: "* ]]
    [[ "${output}" == *"Slowest tests (top 1 of 1, "* ]]
    [[ "${output}" == *"0.50s  Tests.Good"* ]]
}

@test "the reports warn and succeed when python3 is not installed" {
    local _dir="${BATS_TEST_TMPDIR}/results" _empty="${BATS_TEST_TMPDIR}/empty-path"
    mkdir -p "${_empty}"
    write_trx "${_dir}/a.trx" "Tests.Slow=00:00:03.0000000"

    run_report report_slow_tests_trx "${_dir}" PATH="${_empty}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"WARNING: python3 is not installed, so the slow trx report is skipped"* ]]
}

# ── slowest tests (bats JUnit report) ─────────────────────────────────────────

@test "slowest tests reads a bats JUnit report, naming each test by its file" {
    local _report="${BATS_TEST_TMPDIR}/report.xml"
    cat > "${_report}" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites time="3.310">
<testsuite name="a.bats" tests="2" failures="1" errors="0" skipped="0" time="3.310">
    <testcase classname="a.bats" name="fast one" time="0.004" />
    <testcase classname="a.bats" name="slow &amp; failing" time="3.304">
        <failure type="failure">failed</failure>
    </testcase>
</testsuite>
</testsuites>
XML

    run_report report_slow_tests_junit "${_report}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests (top 2 of 2, warning above 2s):"* ]]
    [[ "${output}" == *"3.30s  a.bats: slow & failing"* ]]
    [[ "${output}" == *"WARNING: slow test a.bats: slow & failing 3.30s"* ]]
    [[ "${output}" != *"WARNING: slow test a.bats: fast one"* ]]
}

# ── slowest build parts (MSBuild log) ─────────────────────────────────────────

@test "slowest build parts lists projects, targets, analyzers and generators and warns on the share and seconds thresholds" {
    local _log="${BATS_TEST_TMPDIR}/build.log"
    write_build_log "${_log}"

    run_report report_slow_build "${_log}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest build parts (build took 60.0s, warning above 25% of the build or 30s):"* ]]
    [[ "${output}" == *"40.00s    67%  App.Tests"* ]]
    [[ "${output}" == *"10.94s    18%  App"* ]]
    [[ "${output}" == *"16.52s    28%  CoreCompile"* ]]
    # Waiting for referenced projects is not a slow target of its own.
    [[ "${output}" != *"ResolveProjectReferences"* ]]
    # Analyzer time is summed over both compiles; rule rows are not listed.
    [[ "${output}" == *"15.00s    25%  SlowAnalyzer"* ]]
    [[ "${output}" == *"0.00s     0%  TinyAnalyzer"* ]]
    [[ "${output}" != *"SlowAnalyzer.Rules"* ]]
    [[ "${output}" == *"0.80s     1%  EnumGenerator.Package"* ]]
    [ "$(printf '%s\n' "${output}" | grep '^WARNING')" = "WARNING: slow build part: project App.Tests 40.00s (67% of the build)
WARNING: slow build part: target CoreCompile 16.52s (28% of the build)" ]
}

@test "SLOW_BUILD_SHARE_PERCENT and SLOW_BUILD_THRESHOLD_SECONDS change the build warnings" {
    local _log="${BATS_TEST_TMPDIR}/build.log"
    write_build_log "${_log}"

    run_report report_slow_build "${_log}" SLOW_BUILD_SHARE_PERCENT=100 SLOW_BUILD_THRESHOLD_SECONDS=10
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"warning above 100% of the build or 10s):"* ]]
    [ "$(printf '%s\n' "${output}" | grep -c '^WARNING: slow build part')" -eq 3 ]
    [[ "${output}" == *"WARNING: slow build part: project App 10.94s (18% of the build)"* ]]

    run_report report_slow_build "${_log}" SLOW_BUILD_SHARE_PERCENT=100 SLOW_BUILD_THRESHOLD_SECONDS=100
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" != *"WARNING"* ]]
}

@test "slowest build parts with no performance summary or no log says so and succeeds" {
    local _log="${BATS_TEST_TMPDIR}/build.log"
    printf 'Build FAILED.\n' > "${_log}"

    run_report report_slow_build "${_log}"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest build parts: no build performance summary found"* ]]

    run_report report_slow_build "${BATS_TEST_TMPDIR}/missing.log"
    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest build parts: no build log found"* ]]
}

# ── buildtest ─────────────────────────────────────────────────────────────────

# make_dotnet_stub <dir> <log> <build log fixture> <trx fixture>
# Writes a stub `dotnet` to <dir>/dotnet that logs each call to <log> and
# succeeds. It reports a pre-release SDK, so buildtest skips its benchmark
# step, and lists cscleanup as an installed tool. Its `build` copies <build
# log fixture> to the -flp logfile; its `test` copies <trx fixture> into the
# --results-directory, then exits with $FAKE_TEST_STATUS (default 0).
make_dotnet_stub() {
    mkdir -p "$1"
    cat > "$1/dotnet" << STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$2"
case "\$1" in
    --version) printf '11.0.100-rc.3\n' ;;
    tool)
        printf 'Package Id                        Version      Commands\n'
        printf 'credfeto.dotnet.repo.formatter    1.0.0        cscleanup\n'
        ;;
    build)
        for _a in "\$@"; do
            case "\$_a" in
                -flp:logfile=*)
                    _file="\${_a#-flp:logfile=}"
                    cp "$3" "\${_file%%;*}"
                    ;;
            esac
        done
        ;;
    test)
        _next=0
        for _a in "\$@"; do
            if [ "\$_next" = 1 ]; then
                mkdir -p "\$_a" && cp "$4" "\$_a/stub.trx"
                _next=0
            fi
            [ "\$_a" = "--results-directory" ] && _next=1
        done
        exit "\${FAKE_TEST_STATUS:-0}"
        ;;
esac
exit 0
STUB
    chmod +x "$1/dotnet"
}

# setup_dotnet_repo [IsPackable]
# Creates a git repo with a solution, project and staged .cs file, plus the
# dotnet stub and its fixtures, and prints the repo path. With an argument,
# the project is packable, so buildtest packs it.
setup_dotnet_repo() {
    local _t="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${_t}/src"
    git -C "${_t}" init --quiet
    git -C "${_t}" config user.email "test@example.com"
    git -C "${_t}" config user.name "Test User"
    if [ -n "${1:-}" ]; then
        printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><IsPackable>true</IsPackable></PropertyGroup></Project>\n' > "${_t}/src/Foo.csproj"
    else
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${_t}/src/Foo.csproj"
    fi
    printf 'class Foo { }\n' > "${_t}/src/Foo.cs"
    printf '<Solution></Solution>\n' > "${_t}/src/Foo.slnx"
    git -C "${_t}" add src
    write_build_log "${BATS_TEST_TMPDIR}/fixture-build.log"
    write_trx "${BATS_TEST_TMPDIR}/fixture.trx" "Foo.Tests.Slow=00:00:04.0000000" "Foo.Tests.Fast=00:00:00.0100000"
    make_dotnet_stub "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/dotnet.log" \
        "${BATS_TEST_TMPDIR}/fixture-build.log" "${BATS_TEST_TMPDIR}/fixture.trx"
    mkdir -p "${BATS_TEST_TMPDIR}/tmp"
    printf '%s' "${_t}"
}

# run_buildtest <repo> [NAME=value ...]
# Runs buildtest from <repo> with the stub dotnet first on PATH, TMPDIR in
# the test's own directory and none of the SLOW_* settings inherited.
run_buildtest() {
    local _repo="$1"
    shift
    cd "${_repo}" || return 1
    run env -u SLOW_TEST_THRESHOLD_SECONDS -u SLOW_TEST_TOP -u SLOW_BUILD_SHARE_PERCENT \
        -u SLOW_BUILD_THRESHOLD_SECONDS -u CLAUDECODE PATH="${BATS_TEST_TMPDIR}/bin:${TEST_PATH}" \
        TMPDIR="${BATS_TEST_TMPDIR}/tmp" "$@" sh "${BUILDTEST}"
}

@test "buildtest writes TRX and a build log, prints both reports, warns on a slow test and still succeeds" {
    local T
    T="$(setup_dotnet_repo)"

    run_buildtest "${T}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    grep -q '^build .* -p:ReportAnalyzer=true -flp:logfile=.*/build.log;verbosity=detailed;PerformanceSummary$' "${BATS_TEST_TMPDIR}/dotnet.log"
    grep -q '^test .* --report-xunit-trx --results-directory ' "${BATS_TEST_TMPDIR}/dotnet.log"
    [[ "${output}" == *"Slowest build parts (build took 60.0s, "* ]]
    [[ "${output}" == *"WARNING: slow build part: target CoreCompile 16.52s (28% of the build)"* ]]
    [[ "${output}" == *"Slowest tests (top 2 of 2, warning above 2s):"* ]]
    [[ "${output}" == *"WARNING: slow test Foo.Tests.Slow 4.00s"* ]]
    # The reports' temporary files are removed.
    [ -z "$(ls -A "${BATS_TEST_TMPDIR}/tmp")" ]
}

@test "buildtest passes the SLOW_* settings through to its reports" {
    local T
    T="$(setup_dotnet_repo)"

    run_buildtest "${T}" SLOW_TEST_THRESHOLD_SECONDS=10 SLOW_TEST_TOP=1 SLOW_BUILD_SHARE_PERCENT=90 SLOW_BUILD_THRESHOLD_SECONDS=50

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests (top 1 of 2, warning above 10s):"* ]]
    [[ "${output}" == *"warning above 90% of the build or 50s):"* ]]
    [[ "${output}" != *"WARNING"* ]]
}

@test "buildtest reports the slowest tests when the tests fail, then fails" {
    local T
    T="$(setup_dotnet_repo)"

    run_buildtest "${T}" FAKE_TEST_STATUS=2

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"WARNING: slow test Foo.Tests.Slow 4.00s"* ]]
    [[ "${output}" == *"Tests Failed"* ]]
    [[ "${output}" =~ buildtest\ timings:\ restore=[0-9]+s\ format=[0-9]+s\ cleanup=[0-9]+s\ build=[0-9]+s\ test=[0-9]+s\ total=[0-9]+s ]]
    [ -z "$(ls -A "${BATS_TEST_TMPDIR}/tmp")" ]
}

@test "buildtest prints one timings line naming the steps that ran" {
    local T
    T="$(setup_dotnet_repo)"

    run_buildtest "${T}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "$(printf '%s\n' "${output}" | grep -c '^buildtest timings:')" -eq 1 ]
    printf '%s\n' "${output}" | grep -qxE 'buildtest timings: restore=[0-9]+s format=[0-9]+s cleanup=[0-9]+s build=[0-9]+s test=[0-9]+s total=[0-9]+s'
}

@test "buildtest's timings line includes pack for a packable project" {
    local T
    T="$(setup_dotnet_repo packable)"

    run_buildtest "${T}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    printf '%s\n' "${output}" | grep -qxE 'buildtest timings: restore=[0-9]+s format=[0-9]+s cleanup=[0-9]+s build=[0-9]+s test=[0-9]+s pack=[0-9]+s total=[0-9]+s'
}

@test "buildtest without a solution prints a timings line with only cscleanup" {
    local T
    T="$(setup_dotnet_repo)"
    git -C "${T}" rm --cached --quiet src/Foo.slnx
    rm "${T}/src/Foo.slnx"

    run_buildtest "${T}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    printf '%s\n' "${output}" | grep -qxE 'buildtest timings: cleanup=[0-9]+s total=[0-9]+s'
    [[ "${output}" != *"Slowest"* ]]
}

# ── run-bats ──────────────────────────────────────────────────────────────────

# make_bats_repo <test body>
# Creates a plain git repo whose test/timing.bats holds a fast test and a
# test named "slow" running <test body>, and prints the repo path.
make_bats_repo() {
    local _t="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${_t}/test"
    git -C "${_t}" init --quiet
    printf '#!/usr/bin/env bats\n@test "fast" {\n  true\n}\n@test "slow" {\n  %s\n}\n' "$1" > "${_t}/test/timing.bats"
    printf '%s' "${_t}"
}

@test "run-bats times each test, lists the slowest and warns on a slow one without failing" {
    skip_unless_bats
    local T
    T="$(make_bats_repo 'sleep 0.3')"

    run_isolated "${T}" "${TEST_PATH}" env SLOW_TEST_THRESHOLD_SECONDS=0.2 SLOW_TEST_TOP=5 "${RUN_BATS}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" =~ ok\ [12]\ slow\ \#\ in\ [0-9]+\ ?ms ]]
    [[ "${output}" == *"Slowest tests (top 2 of 2, warning above 0.2s):"* ]]
    [[ "${output}" =~ WARNING:\ slow\ test\ timing\.bats:\ slow\ 0\.[0-9]{2}s ]]
    [[ "${output}" != *"WARNING: slow test timing.bats: fast"* ]]
}

@test "run-bats lists the slowest tests of a failing suite and still fails" {
    skip_unless_bats
    local T
    T="$(make_bats_repo 'false')"

    run_isolated "${T}" "${TEST_PATH}" "${RUN_BATS}"

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == *"not ok"*"slow"* ]]
    [[ "${output}" == *"Slowest tests (top 2 of 2, warning above 2s):"* ]]
}

@test "run-bats runs a bats older than 1.5.0 without the report options" {
    local T _shim="${BATS_TEST_TMPDIR}/shim"
    T="$(make_bats_repo 'true')"
    mkdir -p "${_shim}"
    # shellcheck disable=SC2016 # intentionally literal, expanded by the shim, not here
    printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Bats 1.2.1"; exit 0; }\nprintf "%%s\\n" "$*" > "%s"\n' \
        "${BATS_TEST_TMPDIR}/bats-args" > "${_shim}/bats"
    chmod +x "${_shim}/bats"

    run_isolated "${T}" "${_shim}:${TEST_PATH}" "${RUN_BATS}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "$(cat "${BATS_TEST_TMPDIR}/bats-args")" == *"--recursive"* ]]
    [[ "$(cat "${BATS_TEST_TMPDIR}/bats-args")" != *"--report-formatter"* ]]
    [[ "${output}" != *"Slowest tests"* ]]
}

@test "a commit through the hook prints the bats slowest tests block that pre-commit would hide" {
    skip_unless_bats
    command -v pre-commit > /dev/null 2>&1 || skip "pre-commit not installed"
    local T
    T="$(make_repo feature/slow-bats)"
    printf 'repos:
  - repo: local
    hooks:
      - id: bats
        name: run bats tests
        entry: %s
        language: system
        types: [text]
        pass_filenames: true
        require_serial: true
' "${RUN_BATS}" > "${T}/.pre-commit-config.yaml"
    mkdir -p "${T}/test"
    printf '#!/usr/bin/env bats\n@test "naps" {\n  sleep 0.3\n}\n' > "${T}/test/nap.bats"
    git -C "${T}" add .pre-commit-config.yaml test/nap.bats

    run_isolated "${T}" "${TEST_PATH}" env SLOW_TEST_THRESHOLD_SECONDS=0.2 sh "${HOOK}"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [[ "${output}" == *"Slowest tests (top 1 of 1, warning above 0.2s):"* ]]
    [[ "${output}" =~ WARNING:\ slow\ test\ nap\.bats:\ naps\ 0\.[0-9]{2}s ]]
    [ ! -e "${T}/.git/run-bats-slowest-tests" ]
}

skip_unless_bats() {
    command -v bats > /dev/null 2>&1 || skip "bats not installed"
}
