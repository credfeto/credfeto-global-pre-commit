#! /bin/sh
# Shared helper sourced by buildtest. Not intended to be run directly.
#
# format_dotnet_sources() applies `dotnet format` (IDE* style and analyzer
# fixes) to the target .cs files, then cscleanup
# (Credfeto.DotNet.Repo.Formatter: layout and ordering) to the target .cs and
# .csproj files, and re-stages every file it targeted. It runs inside
# buildtest, after buildtest's single solution restore and before its build,
# so `dotnet format` can skip a restore of its own and the build compiles the
# formatted source.
#
# Depends on the caller already defining die(), info(), success() and
# require_dotnet_tool(), and on lib/mode-arg.sh having been sourced and
# parse_all_files_mode_arg() having set MODE: the target files are the staged
# ones, or every tracked one in all-files mode (see git_target_files).
#
# It sets DOTNET_FORMAT_SECONDS and CSCLEANUP_SECONDS to how long each step
# took, in whole seconds, when that step ran, for buildtest's timings line.

FORMATTER_TOOL_CMD="cscleanup"
FORMATTER_TOOL_PKG="Credfeto.DotNet.Repo.Formatter"

# format_dotnet_sources <solution> <restored>
#
# <solution> is the solution file `dotnet format` loads, and the one the
# caller restored; when it is empty, `dotnet format` is skipped and only
# cscleanup runs. <restored> is 1 when the caller has already restored
# <solution>, so `dotnet format` runs with --no-restore; any other value
# falls back to a normal `dotnet format` run, which restores the solution
# itself.
#
# `dotnet format --include` gets paths relative to the repository root and
# runs from there: it matches an absolute path against nothing, reports
# "Formatted 0 of N files" and exits 0, so an absolute path silently skips
# every fix.
format_dotnet_sources() {
    _fmt_solution="$1"
    _fmt_restored="$2"

    _fmt_scope=staged
    [ "$MODE" = "all-files" ] && _fmt_scope=tracked

    _fmt_files=$(git_target_files '\.(cs|csproj)$')
    if [ -z "$_fmt_files" ]; then
        info "No ${_fmt_scope} .cs or .csproj files, skipping formatter"
        return 0
    fi

    require_dotnet_tool "$FORMATTER_TOOL_CMD" "$FORMATTER_TOOL_PKG"

    _fmt_root=$(git rev-parse --show-toplevel) || die "Could not find the repository root"

    # dotnet format does not apply to .csproj files.
    _fmt_cs_files=$(printf '%s\n' "$_fmt_files" | grep -E '\.cs$')
    if [ -n "$_fmt_cs_files" ]; then
        if [ -z "$_fmt_solution" ]; then
            info "No solution file found — skipping dotnet format"
        else
            dotnet format --version > /dev/null 2>&1 \
                || die "dotnet format is not available in this SDK (missing dotnet-format component): cannot format ${_fmt_scope} .cs files"

            set -- "$_fmt_solution"
            if [ "$_fmt_restored" = "1" ]; then
                set -- "$@" --no-restore
                info "Applying dotnet format to ${_fmt_scope} .cs files (no restore: the solution is already restored)..."
            else
                info "Applying dotnet format to ${_fmt_scope} .cs files (no earlier restore, so dotnet format restores the solution itself)..."
            fi
            set -- "$@" --include
            while IFS= read -r _fmt_file; do
                set -- "$@" "$_fmt_file"
            done << EOF
$_fmt_cs_files
EOF
            _fmt_started=$(date +%s)
            (cd "$_fmt_root" && dotnet format "$@") || die "dotnet format failed"
            # shellcheck disable=SC2034 # read by buildtest's timings line
            DOTNET_FORMAT_SECONDS=$(($(date +%s) - _fmt_started))
            success "dotnet format applied"
        fi
    fi

    # cscleanup takes full paths, in a single invocation.
    set --
    while IFS= read -r _fmt_file; do
        set -- "$@" "${_fmt_root}/${_fmt_file}"
    done << EOF
$_fmt_files
EOF

    info "Applying cscleanup formatting to ${_fmt_scope} .cs and .csproj files..."
    _fmt_started=$(date +%s)
    dotnet "$FORMATTER_TOOL_CMD" "$@" || die "cscleanup format failed"
    # shellcheck disable=SC2034 # read by buildtest's timings line
    CSCLEANUP_SECONDS=$(($(date +%s) - _fmt_started))

    # Re-stage everything either step may have changed, in one git add call,
    # only once both steps have succeeded.
    git add -- "$@" || die "Failed to re-stage the formatted files"

    success "dotnet format and cscleanup formatting applied and staged"
}
