#! /bin/sh
# Shared helper sourced by buildtest and run-bats. Not intended to be run
# directly.
#
# Warning-only reports of where a commit's time goes: the slowest tests (from
# the TRX files `dotnet test --report-xunit-trx` writes, or the JUnit report
# `bats --report-formatter junit` writes) and the slowest parts of a .NET
# build (from an MSBuild file log written with PerformanceSummary at detailed
# verbosity, built with -p:ReportAnalyzer=true). Nothing here ever fails: a
# missing python3, a missing or malformed report, or a bad setting prints a
# WARNING line and the caller carries on.
#
# Thresholds come from the environment, with these defaults:
#   SLOW_TEST_THRESHOLD_SECONDS  2   a test taking longer is a slow test
#   SLOW_TEST_TOP                10  how many of the slowest tests to list
#   SLOW_BUILD_SHARE_PERCENT     25  a project or target taking a larger share
#                                    of the build's elapsed time is slow
#   SLOW_BUILD_THRESHOLD_SECONDS 30  a project or target taking longer is slow
# The names match the CI template's, so local and CI runs behave alike.

# report_slow_tests_trx <directory>
# Lists the slowest tests in every *.trx file under <directory>.
report_slow_tests_trx() {
    _slow_report_run trx "$1"
}

# report_slow_tests_junit <file>
# Lists the slowest tests in the JUnit XML report <file>.
report_slow_tests_junit() {
    _slow_report_run junit "$1"
}

# report_slow_build <log file>
# Lists the slowest projects, targets, analyzers and source generators in the
# MSBuild file log <log file>, and warns on slow projects and targets.
report_slow_build() {
    _slow_report_run msbuild "$1"
}

_slow_report_run() {
    if ! command -v python3 > /dev/null 2>&1; then
        printf '\nWARNING: python3 is not installed, so the slow %s report is skipped\n' "$1"
        return 0
    fi
    python3 - "$@" << 'PYTHON' || printf '\nWARNING: the slow %s report failed, ignoring it\n' "$1"
import glob
import os
import re
import sys
import xml.etree.ElementTree as ElementTree

BUILD_TOP = 5
# Targets whose time is spent waiting for other projects to build, so would
# count those projects a second time.
WAITING_TARGETS = {"ResolveProjectReferences", "_GetProjectReferenceTargetFrameworkProperties"}
TRX_DURATION = re.compile(r"^(?:(\d+)\.)?(\d+):(\d+):(\d+(?:\.\d+)?)$")
NODE_PREFIX = re.compile(r"^\s*\d+(?::\d+)?>")
SUMMARY_LINE = re.compile(r"^\s*(\d+) ms\s+(.+?)\s+(\d+) calls\s*$")
ELAPSED = re.compile(r"^Time Elapsed (\d+):(\d+):(\d+(?:\.\d+)?)\s*$")
TOTAL_TIME = re.compile(r"^\s*Total (analyzer|generator) execution time: ")
TABLE_ROW = re.compile(r"^\s*(<?[\d.]+)\s+<?\d+\s+(\S.*?)\s*$")


def warn(message):
    print(f"WARNING: {message}")


def setting(name, default, integer):
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw) if integer else float(raw)
    except ValueError:
        value = -1
    if value < 0 or value != value:
        warn(f"{name}={raw} is not a non-negative number, using {default}")
        return default
    return value


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def read_xml(path):
    try:
        return ElementTree.parse(path).getroot()
    except (ElementTree.ParseError, OSError) as error:
        warn(f"could not read test results {os.path.basename(path)}: {error}")
        return None


def trx_duration(text):
    match = TRX_DURATION.match(text.strip())
    if not match:
        return None
    days, hours, minutes, seconds = match.groups()
    return int(days or 0) * 86400 + int(hours) * 3600 + int(minutes) * 60 + float(seconds)


def trx_results(directory):
    results = []
    pattern = os.path.join(glob.escape(directory), "**", "*.trx")
    for path in sorted(glob.glob(pattern, recursive=True)):
        root = read_xml(path)
        if root is None:
            continue
        for element in root.iter():
            if local_name(element.tag) != "UnitTestResult":
                continue
            name = element.get("testName")
            duration = trx_duration(element.get("duration", ""))
            if name and duration is not None:
                results.append((name, duration))
    return results


def junit_results(path):
    results = []
    if not os.path.isfile(path):
        return results
    root = read_xml(path)
    if root is None:
        return results
    for element in root.iter():
        if local_name(element.tag) != "testcase":
            continue
        name = element.get("name")
        suite = element.get("classname")
        try:
            duration = float(element.get("time", ""))
        except ValueError:
            continue
        if name:
            results.append((f"{suite}: {name}" if suite else name, duration))
    return results


def report_tests(results):
    top = setting("SLOW_TEST_TOP", 10, True)
    threshold = setting("SLOW_TEST_THRESHOLD_SECONDS", 2, False)
    print()
    if not results:
        print("Slowest tests: no test results found")
        return
    ranked = sorted(results, key=lambda result: (-result[1], result[0]))
    shown = ranked[:top]
    print(f"Slowest tests (top {len(shown)} of {len(ranked)}, warning above {threshold:g}s):")
    for name, seconds in shown:
        print(f"  {seconds:9.2f}s  {name}")
    for name, seconds in ranked:
        if seconds > threshold:
            warn(f"slow test {name} {seconds:.2f}s")


def project_name(path):
    return os.path.splitext(os.path.basename(path.replace("\\", "/")))[0]


def add(totals, name, seconds):
    totals[name] = totals.get(name, 0.0) + seconds


def read_build_log(path):
    sections = {"project": {}, "target": {}, "analyzer": {}, "generator": {}}
    elapsed = None
    section = None
    table = None
    with open(path, encoding="utf-8", errors="replace") as log:
        for raw in log:
            line = NODE_PREFIX.sub("", raw.rstrip("\n"))
            stripped = line.strip()
            match = TOTAL_TIME.match(line)
            if match:
                table = match.group(1)
                continue
            if table:
                if stripped.startswith("Time (s)"):
                    continue
                row = TABLE_ROW.match(line)
                if row and ", Version=" in row.group(2):
                    seconds = 0.0 if row.group(1).startswith("<") else float(row.group(1))
                    add(sections[table], row.group(2).split(",", 1)[0], seconds)
                    continue
                if row:
                    continue
                table = None
            if stripped.endswith("Performance Summary:"):
                section = {
                    "Project Performance Summary:": "project",
                    "Target Performance Summary:": "target",
                }.get(stripped)
                continue
            match = ELAPSED.match(stripped)
            if match:
                hours, minutes, seconds = match.groups()
                elapsed = int(hours) * 3600 + int(minutes) * 60 + float(seconds)
                section = None
                continue
            match = SUMMARY_LINE.match(line)
            if not match or section is None:
                if not stripped:
                    continue
                if not match:
                    section = None
                continue
            milliseconds, name = int(match.group(1)), match.group(2)
            if section == "project":
                # Only the projects themselves: the targets nested under each
                # one are the ones other projects called on it.
                if name.lower().endswith(("proj", ".sln", ".slnx")):
                    add(sections["project"], project_name(name), milliseconds / 1000)
            elif name not in WAITING_TARGETS:
                add(sections["target"], name, milliseconds / 1000)
    return sections, elapsed


def share(seconds, elapsed):
    if not elapsed:
        return ""
    return f"  {seconds * 100 / elapsed:4.0f}%"


def report_build(path):
    share_limit = setting("SLOW_BUILD_SHARE_PERCENT", 25, False)
    seconds_limit = setting("SLOW_BUILD_THRESHOLD_SECONDS", 30, False)
    print()
    if not os.path.isfile(path):
        print("Slowest build parts: no build log found")
        return
    sections, elapsed = read_build_log(path)
    if not sections["project"] and not sections["target"]:
        print("Slowest build parts: no build performance summary found")
        return
    took = f"build took {elapsed:.1f}s, " if elapsed else ""
    print(f"Slowest build parts ({took}warning above {share_limit:g}% of the build or {seconds_limit:g}s):")
    headings = {
        "project": "Projects (including time spent waiting for the projects they reference)",
        "target": "Targets (summed over every project and parallel node)",
        "analyzer": "Analyzers (summed over every project)",
        "generator": "Source generators (summed over every project)",
    }
    warnings = []
    for kind, heading in headings.items():
        ranked = sorted(sections[kind].items(), key=lambda item: (-item[1], item[0]))
        if not ranked:
            continue
        print(f"  {heading}:")
        for name, seconds in ranked[:BUILD_TOP]:
            print(f"  {seconds:9.2f}s{share(seconds, elapsed)}  {name}")
        if kind not in ("project", "target"):
            continue
        for name, seconds in ranked:
            over_share = elapsed and seconds * 100 / elapsed > share_limit
            if over_share or seconds > seconds_limit:
                percent = f" ({seconds * 100 / elapsed:.0f}% of the build)" if elapsed else ""
                warnings.append(f"slow build part: {kind} {name} {seconds:.2f}s{percent}")
    for message in warnings:
        warn(message)


def main(mode, target):
    if mode == "trx":
        report_tests(trx_results(target))
    elif mode == "junit":
        report_tests(junit_results(target))
    elif mode == "msbuild":
        report_build(target)
    else:
        raise SystemExit(f"unknown report {mode}")


main(sys.argv[1], sys.argv[2])
PYTHON
    return 0
}
