#!/usr/bin/env bats
# Acceptance tests for src/scripts/lib/dotnet-tool.sh: where dotnet_tool_installed
# finds a dotnet tool (a local manifest in the working directory or in HOME, a
# global install on PATH, or a global install reached through
# $HOME/.dotnet/tools), how run_dotnet_tool runs it from there, and how the
# method found is cached in an exported DOTNET_TOOL_RUN_<CMD> variable.
#
# Uses a fake `dotnet` on PATH that logs every call and lists the widget tool
# locally only when run from $FAKE_LOCAL_DIR, and globally only when
# $FAKE_GLOBAL is set.

# The scripts run_lib is given are expanded by the inner sh, not here.
# shellcheck disable=SC2016

load test_helper

bats_require_minimum_version 1.5.0

LIB="${REPO_DIR}/src/scripts/lib/dotnet-tool.sh"

setup() {
    BIN="${BATS_TEST_TMPDIR}/bin"
    TOOL_BIN="${BATS_TEST_TMPDIR}/tool-bin"
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    WORK="${BATS_TEST_TMPDIR}/work"
    LOG="${BATS_TEST_TMPDIR}/dotnet.log"
    mkdir -p "${BIN}" "${TOOL_BIN}" "${FAKE_HOME}" "${WORK}"
    : > "${LOG}"
    cat > "${BIN}/dotnet" << 'STUB'
#!/bin/sh
printf '%s|%s\n' "$(pwd -P)" "$*" >> "$FAKE_DOTNET_LOG"
if [ "$1" = tool ] && [ "$2" = list ]; then
    printf 'Package Id          Version      Commands\n'
    printf -- '--------------------------------------------\n'
    if [ "$3" = --global ]; then
        [ -n "$FAKE_GLOBAL" ] && printf 'acme.widget.tool    1.0.0        widget\n'
    elif [ -n "$FAKE_LOCAL_DIR" ] && [ "$(pwd -P)" = "$FAKE_LOCAL_DIR" ]; then
        printf 'acme.widget.tool    1.0.0        widget      dotnet-tools.json\n'
    fi
    exit 0
fi
printf 'dotnet ran: %s\n' "$*"
STUB
    chmod +x "${BIN}/dotnet"
}

# write_tool <file> <label>
# Writes an executable that prints "<label> ran: <its arguments>".
write_tool() {
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\nprintf "%s ran: %%s\\n" "$*"\n' "$2" > "$1"
    chmod +x "$1"
}

# run_lib <script> [NAME=value ...]
# Runs <script> in sh from WORK after sourcing the lib, with the fake dotnet
# and TOOL_BIN on PATH, HOME at FAKE_HOME and die() printing DIED: <message>.
run_lib() {
    local _script="$1"
    shift
    cd "${WORK}" || return 1
    run env -u CLAUDECODE PATH="${BIN}:${TOOL_BIN}:${TEST_PATH}" HOME="${FAKE_HOME}" \
        FAKE_DOTNET_LOG="${LOG}" "$@" sh -c '
        die() { printf "DIED: %s\n" "$*"; exit 1; }
        is_ai_agent() { [ "${CLAUDECODE}" = "1" ]; }
        . "$1"
        '"${_script}" _ "${LIB}"
}

# tool_list_calls
# Prints how many times the fake dotnet was asked for a tool list.
tool_list_calls() {
    grep -c '|tool list' "${LOG}" || true
}

@test "dotnet_tool_cache_var upper-cases the command and replaces characters a variable name cannot hold" {
    run_lib 'dotnet_tool_cache_var code-analysis; printf "\n"; dotnet_tool_cache_var my.tool-x2; printf "\n"'

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "DOTNET_TOOL_RUN_CODE_ANALYSIS" ]
    [ "${lines[1]}" = "DOTNET_TOOL_RUN_MY_TOOL_X2" ]
}

@test "a tool in the working directory's local manifest runs as dotnet <cmd> and is cached as local" {
    run_lib 'run_dotnet_tool widget Acme.Widget.Tool a "b c"; sh -c "printf \"child=%s\n\" \"\$DOTNET_TOOL_RUN_WIDGET\""' \
        FAKE_LOCAL_DIR="$(cd "${WORK}" && pwd -P)"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "dotnet ran: widget a b c" ]
    [ "${lines[1]}" = "child=local" ]
}

@test "a tool in HOME's local manifest is found from a directory without one and runs as dotnet <cmd>" {
    run_lib 'run_dotnet_tool widget Acme.Widget.Tool x; printf "cached=%s\n" "$DOTNET_TOOL_RUN_WIDGET"' \
        FAKE_LOCAL_DIR="$(cd "${FAKE_HOME}" && pwd -P)"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "dotnet ran: widget x" ]
    [ "${lines[1]}" = "cached=local" ]
    # The tool runs from the working directory, not from HOME.
    grep -qx "$(cd "${WORK}" && pwd -P)|widget x" "${LOG}"
}

@test "a global tool on PATH runs as <cmd> and is cached as global" {
    write_tool "${TOOL_BIN}/widget" "path widget"

    run_lib 'run_dotnet_tool widget Acme.Widget.Tool y; printf "cached=%s\n" "$DOTNET_TOOL_RUN_WIDGET"' FAKE_GLOBAL=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "path widget ran: y" ]
    [ "${lines[1]}" = "cached=global" ]
}

@test "a global tool not on PATH runs from HOME/.dotnet/tools and is cached as home" {
    write_tool "${FAKE_HOME}/.dotnet/tools/widget" "home widget"

    run_lib 'run_dotnet_tool widget Acme.Widget.Tool z; printf "cached=%s\n" "$DOTNET_TOOL_RUN_WIDGET"' FAKE_GLOBAL=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "home widget ran: z" ]
    [ "${lines[1]}" = "cached=home" ]
}

@test "a global tool in HOME/.dotnet/tools is preferred over a same-named command on PATH" {
    write_tool "${FAKE_HOME}/.dotnet/tools/widget" "home widget"
    write_tool "${TOOL_BIN}/widget" "path widget"

    run_lib 'run_dotnet_tool widget Acme.Widget.Tool z' FAKE_GLOBAL=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${output}" = "home widget ran: z" ]
}

@test "a script on PATH with the tool's name does not find itself as the global tool" {
    # The pre-commit hook puts its scripts directory on PATH, and buildcheck is
    # the name of both a script there and a dotnet tool.
    cat > "${TOOL_BIN}/widget" << SCRIPT
#!/bin/sh
printf 'wrapper started\n'
die() { printf "DIED: %s\n" "\$*"; exit 1; }
is_ai_agent() { return 1; }
. "${LIB}"
run_dotnet_tool widget Acme.Widget.Tool
SCRIPT
    chmod +x "${TOOL_BIN}/widget"

    cd "${WORK}" || return 1
    # With no shim in HOME/.dotnet/tools to fall back on, the run fails as a
    # missing command rather than calling the wrapper again.
    run -127 timeout 20 env -u CLAUDECODE PATH="${BIN}:${TOOL_BIN}:${TEST_PATH}" HOME="${FAKE_HOME}" \
        FAKE_DOTNET_LOG="${LOG}" FAKE_GLOBAL=1 widget

    [ "$(printf '%s\n' "${output}" | grep -c 'wrapper started')" -eq 1 ] \
        || fail_test "the wrapper ran itself again: ${output}"
}

@test "a tool that is not installed fails with a not installed error and is not cached" {
    run_lib 'dotnet_tool_installed widget Acme.Widget.Tool || printf "missing cached=[%s]\n" "${DOTNET_TOOL_RUN_WIDGET:-}"; run_dotnet_tool widget Acme.Widget.Tool'

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [ "${lines[0]}" = "missing cached=[]" ]
    [ "${lines[1]}" = "DIED: widget (Acme.Widget.Tool) dotnet tool is not installed" ]
    # The failed lookup is not cached, so the second call looks again.
    [ "$(tool_list_calls)" -eq 6 ]
}

@test "a listed command from a different package does not count as installed" {
    run_lib 'dotnet_tool_installed widget Other.Package && printf "found\n"; printf "done\n"' \
        FAKE_LOCAL_DIR="$(cd "${WORK}" && pwd -P)" FAKE_GLOBAL=1

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${output}" = "done" ]
}

@test "a resolved tool is not looked up again in the same process" {
    run_lib 'run_dotnet_tool widget Acme.Widget.Tool 1; run_dotnet_tool widget Acme.Widget.Tool 2' \
        FAKE_LOCAL_DIR="$(cd "${WORK}" && pwd -P)"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[1]}" = "dotnet ran: widget 2" ]
    [ "$(tool_list_calls)" -eq 1 ]
}

@test "a run method inherited from the parent process is used without looking the tool up" {
    write_tool "${FAKE_HOME}/.dotnet/tools/widget" "home widget"

    run_lib 'run_dotnet_tool widget Acme.Widget.Tool q' DOTNET_TOOL_RUN_WIDGET=home

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${output}" = "home widget ran: q" ]
    [ "$(tool_list_calls)" -eq 0 ]
}

@test "an inherited run method that is not a known method is ignored and the tool is looked up" {
    run_lib 'run_dotnet_tool widget Acme.Widget.Tool q; printf "cached=%s\n" "$DOTNET_TOOL_RUN_WIDGET"' \
        DOTNET_TOOL_RUN_WIDGET='rm -rf /' FAKE_LOCAL_DIR="$(cd "${WORK}" && pwd -P)"

    [ "${status}" -eq 0 ] || fail_with_run_output "${status}" "${output}" 0
    [ "${lines[0]}" = "dotnet ran: widget q" ]
    [ "${lines[1]}" = "cached=local" ]
}

@test "an AI agent missing a tool from a repository with a tool manifest is told to add it to the manifest" {
    git -C "${WORK}" init --quiet
    mkdir -p "${WORK}/.config"
    printf '{}\n' > "${WORK}/.config/dotnet-tools.json"

    run_lib 'run_dotnet_tool widget Acme.Widget.Tool' CLAUDECODE=1

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == "DIED: dotnet-tools.json exists in this repository but Acme.Widget.Tool (widget) is not installed"* ]]
}

@test "an AI agent missing a tool is told the operator must provide it" {
    run_lib 'run_dotnet_tool widget Acme.Widget.Tool' CLAUDECODE=1

    [ "${status}" -eq 1 ] || fail_with_run_output "${status}" "${output}" 1
    [[ "${output}" == "DIED: Required package (Acme.Widget.Tool) is not installed so cannot run widget."* ]]
}
