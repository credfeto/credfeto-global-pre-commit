#! /bin/sh
# Shared helper sourced by the pre-commit hook and by the scripts that run
# dotnet tools. Not intended to be run directly.
#
# dotnet_tool_installed() finds where a dotnet tool is installed, and
# run_dotnet_tool() runs it from there:
#   1. a local tool manifest found from the working directory: run
#      as `dotnet <cmd>`;
#   2. a global install whose command is on PATH: run as `<cmd>`;
#   3. a global install that is not on PATH: run as $HOME/.dotnet/tools/<cmd>.
#
# The method found is exported as DOTNET_TOOL_RUN_<CMD> (see
# dotnet_tool_cache_var), so the scripts the pre-commit hook runs as child
# processes reuse it instead of running `dotnet tool list` again.
#
# Depends on the caller already defining die() and is_ai_agent().

# dotnet_tool_cache_var <cmd>
# Prints the name of the variable caching <cmd>'s run method: <cmd> upper-cased,
# with every character that cannot appear in a variable name replaced by _.
dotnet_tool_cache_var() {
    printf 'DOTNET_TOOL_RUN_%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
}

# _dotnet_tool_listed <cmd> <pkg> [dotnet tool list argument ...]
# Returns 0 if <cmd> and <pkg> are on the same row of `dotnet tool list`.
_dotnet_tool_listed() {
    _dtl_cmd="$1"
    _dtl_pkg="$2"
    shift 2
    dotnet tool list "$@" 2>/dev/null \
        | awk -v cmd="$_dtl_cmd" -v pkg="$_dtl_pkg" \
            'tolower($3)==tolower(cmd) && tolower($1)==tolower(pkg){found=1} END{exit !found}'
}

# _dotnet_tool_global_method <cmd>
# Prints how to run a globally installed <cmd>. The shim in $HOME/.dotnet/tools
# comes first because the pre-commit hook puts its scripts directory on PATH,
# and buildcheck is the name of both a script there and a dotnet tool: a PATH
# lookup that finds the running script itself would only call itself again.
_dotnet_tool_global_method() {
    if [ -x "$HOME/.dotnet/tools/$1" ]; then
        printf 'home'
        return 0
    fi
    _dtg_path=$(command -v "$1" 2>/dev/null)
    if [ -n "$_dtg_path" ] && [ "$(readlink -f "$_dtg_path")" != "$(readlink -f "$0")" ]; then
        printf 'global'
        return 0
    fi
    printf 'home'
}

# dotnet_tool_method <cmd>
# Prints <cmd>'s cached run method (local, global or home), or nothing when it
# has not been resolved yet.
dotnet_tool_method() {
    _dtm_var=$(dotnet_tool_cache_var "$1")
    _dtm_value=
    eval "_dtm_value=\${$_dtm_var:-}"
    case "$_dtm_value" in
        local | global | home) printf '%s' "$_dtm_value" ;;
    esac
}

# dotnet_tool_installed <cmd> <pkg>
# Returns 0 if <cmd> from package <pkg> is installed, caching and exporting how
# to run it. A tool that is not installed is not cached, so a later call looks
# again.
dotnet_tool_installed() {
    [ -n "$(dotnet_tool_method "$1")" ] && return 0

    if _dotnet_tool_listed "$1" "$2"; then
        _dti_method=local
    elif _dotnet_tool_listed "$1" "$2" --global; then
        _dti_method=$(_dotnet_tool_global_method "$1")
    else
        return 1
    fi

    _dti_var=$(dotnet_tool_cache_var "$1")
    eval "$_dti_var=\$_dti_method"
    export "${_dti_var?}"
    return 0
}

# require_dotnet_tool <cmd> <pkg>
# Dies unless <cmd> from package <pkg> is installed.
require_dotnet_tool() {
    dotnet_tool_installed "$1" "$2" && return 0
    if is_ai_agent; then
        _rdt_repo=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$_rdt_repo" ] && { [ -f "$_rdt_repo/.config/dotnet-tools.json" ] || [ -f "$_rdt_repo/dotnet-tools.json" ]; }; then
            die "dotnet-tools.json exists in this repository but $2 ($1) is not installed: add $2 to the manifest and run 'dotnet tool restore'. Do not install it directly."
        fi
        die "Required package ($2) is not installed so cannot run $1.  Operator needs to provide this to the environment.  Do not install it yourself"
    fi
    die "$1 ($2) dotnet tool is not installed"
}

# run_dotnet_tool <cmd> <pkg> [argument ...]
# Runs <cmd> from package <pkg> with the given arguments, dying if it is not
# installed, and returns its exit status.
run_dotnet_tool() {
    _rnt_cmd="$1"
    require_dotnet_tool "$1" "$2"
    shift 2
    case "$(dotnet_tool_method "$_rnt_cmd")" in
        local) dotnet "$_rnt_cmd" "$@" ;;
        global) "$_rnt_cmd" "$@" ;;
        *) "$HOME/.dotnet/tools/$_rnt_cmd" "$@" ;;
    esac
}
