#! /bin/sh
# Shared helper sourced by the pre-commit and commit-msg hooks. Not intended
# to be run directly.
#
# The pre-commit hook times each step it runs and, on a successful commit,
# writes the timings to $(git rev-parse --git-dir)/precommit-timings. The
# commit-msg hook then adds them to the commit message as a single
# Pre-commit-Timings trailer and deletes the file. The file holds two lines:
# the run id of the git process that ran the pre-commit hook, and the trailer
# value. See "Pre-commit timings" in README.md for the value's format.

# shellcheck disable=SC2034 # read by the commit-msg hook
PRECOMMIT_TIMINGS_KEY="Pre-commit-Timings"

# The scripted steps, in the order the pre-commit hook runs them and the
# trailer lists them. pre-commit is the pre-commit framework run, listed with
# its hook ids in parentheses, and buildtest is listed with its phases.
PRECOMMIT_TIMINGS_STEPS="check-identity check-merge-commits check-ignored-files check-funfair-props clean-package-lock-registry pre-commit check-changelog check-benchmark-project-names buildcheck buildtest npm-test tsqllint sqlfluff cfn-lint"

PRECOMMIT_TIMINGS_STARTED=$(date +%s)
PRECOMMIT_TIMINGS_RECORDED=""

# timings_file
# Prints the path of the timings file for the current repository.
timings_file() {
    _tf_git_dir=$(git rev-parse --absolute-git-dir 2> /dev/null) || return 1
    printf '%s/precommit-timings\n' "$_tf_git_dir"
}

# timings_run_id
# Prints an id for the git process that is running this hook: the parent's
# PID plus, where /proc can tell, the parent's start time, so a reused PID
# does not match. The pre-commit and commit-msg hooks of one `git commit` are
# both children of the same git process, so their ids match, while a file
# left by an aborted commit carries the id of a git process that has gone.
# PRECOMMIT_TIMINGS_RUN_ID_TEST_OVERRIDE is a test-only escape hatch (bats
# runs each hook from its own shell, so the two never share a parent); never
# set this variable in production shells.
timings_run_id() {
    if [ -n "${PRECOMMIT_TIMINGS_RUN_ID_TEST_OVERRIDE:-}" ]; then
        printf '%s\n' "$PRECOMMIT_TIMINGS_RUN_ID_TEST_OVERRIDE"
        return
    fi
    _tri_started=""
    if [ -r "/proc/$PPID/stat" ]; then
        # The command name in field 2 can hold spaces and parentheses, so the
        # fields are counted from after its closing parenthesis: the start
        # time, field 22, is then field 20.
        _tri_started=$(sed 's/.*) //' "/proc/$PPID/stat" 2> /dev/null | cut -d' ' -f20)
    fi
    printf '%s:%s\n' "$PPID" "$_tri_started"
}

# timings_seconds_since <epoch seconds>
# Prints the whole seconds since <epoch seconds>.
timings_seconds_since() {
    printf '%s\n' "$(($(date +%s) - $1))"
}

# timings_record <step> <value>
# Records <value> (e.g. 4s, or 290s(restore=40s,...)) as <step>'s timing.
timings_record() {
    PRECOMMIT_TIMINGS_RECORDED="${PRECOMMIT_TIMINGS_RECORDED}$1=$2
"
}

# timings_record_with_parts <step> <started epoch seconds> <parts>
# Records the whole seconds since <started> as <step>'s timing, followed by
# <parts> (e.g. restore=40s,build=120s) in parentheses when there are any.
timings_record_with_parts() {
    _trwp_value="$(timings_seconds_since "$2")s"
    if [ -n "$3" ]; then
        _trwp_value="${_trwp_value}($3)"
    fi
    timings_record "$1" "$_trwp_value"
}

# timed_step <step> <command>...
# Runs <command>, records the whole seconds it took as <step>'s timing, and
# returns its exit status.
timed_step() {
    _ts_step=$1
    shift
    _ts_started=$(date +%s)
    _ts_status=0
    "$@" || _ts_status=$?
    timings_record "$_ts_step" "$(timings_seconds_since "$_ts_started")s"
    return "$_ts_status"
}

# timings_value
# Prints the trailer value: the total, then every step in
# PRECOMMIT_TIMINGS_STEPS order, with skipped for a step that did not run.
timings_value() {
    printf '%s' "$PRECOMMIT_TIMINGS_RECORDED" | awk \
        -v steps="$PRECOMMIT_TIMINGS_STEPS" \
        -v total="$(timings_seconds_since "$PRECOMMIT_TIMINGS_STARTED")" '
        {
            split($0, _pair, "=")
            _name = _pair[1]
            recorded[_name] = substr($0, length(_name) + 2)
        }
        END {
            _line = "total=" total "s"
            _count = split(steps, _steps, " ")
            for (_i = 1; _i <= _count; _i++) {
                _value = (_steps[_i] in recorded) ? recorded[_steps[_i]] : "skipped"
                _line = _line " " _steps[_i] "=" _value
            }
            print _line
        }'
}

# timings_print
# Prints the total and each step's timing, one per line, so the commit output
# shows where the time went. Steps that did not run are left out.
timings_print() {
    printf '\n\033[32m->\033[0m Pre-commit timings\n'
    timings_value | tr ' ' '\n' | grep -v '=skipped$' | sed 's/^/    /'
}

# timings_write_file
# Writes the run id and the trailer value to the timings file, for the
# commit-msg hook. Never fails the commit: the timings are diagnostics.
timings_write_file() {
    _twf_file=$(timings_file) || return 0
    {
        timings_run_id
        timings_value
    } > "$_twf_file" 2> /dev/null || rm -f "$_twf_file"
}

# timings_remove_file
# Removes any timings file an earlier, aborted commit left behind.
timings_remove_file() {
    _trf_file=$(timings_file) || return 0
    rm -f "$_trf_file"
}

# The escape character, for the ANSI colour codes pre-commit writes with
# --color always.
PRECOMMIT_TIMINGS_ESC=$(printf '\033')

# precommit_display_filter
# Reads `pre-commit run --verbose` output on stdin and prints what a run
# without --verbose would have shown: a passed or skipped hook's status line
# only, and a failed hook's whole block bar its duration. --verbose is needed
# only for the durations, which precommit_hook_timings reads from the
# unfiltered output. A status line ends with dots and Passed, Failed or
# Skipped, and is recognised only when the `- hook id:` line follows it,
# because a hook's own output can end the same way.
precommit_display_filter() {
    awk -v esc="$PRECOMMIT_TIMINGS_ESC" '
        function plain(s) {
            gsub(esc "\\[[0-9;]*m", "", s)
            return s
        }
        function emit(s) {
            print s
            fflush()
        }
        {
            _line = $0
            _plain = plain(_line)
            if (pending != "") {
                if (_plain ~ /^- hook id: /) {
                    emit(pending)
                    state = (plain(pending) ~ /Failed$/) ? "failed" : "quiet"
                    pending = ""
                    if (state == "failed") {
                        emit(_line)
                    }
                    next
                }
                if (state != "quiet") {
                    emit(pending)
                }
                pending = ""
            }
            if (_plain ~ /\.(\(no files to check\))?(Passed|Failed|Skipped)$/) {
                pending = _line
                next
            }
            if (_plain ~ /^\[(INFO|WARNING|ERROR)\]/) {
                emit(_line)
            } else if (state == "failed") {
                if (_plain !~ /^- duration: /) {
                    emit(_line)
                }
            } else if (state != "quiet") {
                emit(_line)
            }
        }
        END {
            if (pending != "") {
                emit(pending)
            }
        }'
}

# precommit_hook_timings <log>
# Prints the hook timings from a `pre-commit run --verbose` log as
# id=Ns,id=Ns,..., in run order, with skipped for a hook that did not run. A
# hook id that appears more than once is listed once, with the durations of
# its runs added together.
precommit_hook_timings() {
    awk -v esc="$PRECOMMIT_TIMINGS_ESC" '
        {
            gsub(esc "\\[[0-9;]*m", "")
        }
        /^- hook id: / {
            hook = substr($0, length("- hook id: ") + 1)
            if (!(hook in seen)) {
                seen[hook] = 1
                order[++count] = hook
            }
            next
        }
        /^- duration: / && hook != "" {
            _duration = substr($0, length("- duration: ") + 1)
            sub(/s$/, "", _duration)
            ran[hook] = 1
            total[hook] += _duration
            hook = ""
        }
        END {
            for (_i = 1; _i <= count; _i++) {
                _hook = order[_i]
                _value = (_hook in ran) ? sprintf("%gs", total[_hook]) : "skipped"
                _line = _line (_i > 1 ? "," : "") _hook "=" _value
            }
            print _line
        }' "$1"
}

# run_precommit_timed <log> <pre-commit run argument>...
# Runs `pre-commit run` with --verbose, showing its output through
# precommit_display_filter and keeping the unfiltered output in <log>, and
# returns pre-commit's exit status. Colour follows this hook's own stdout,
# because pre-commit's own check would only ever see the pipe.
run_precommit_timed() {
    _rpt_log=$1
    shift
    if [ -t 1 ]; then
        _rpt_color=always
    else
        _rpt_color=never
    fi
    # POSIX sh has no pipefail, so pre-commit's status goes through a file.
    {
        _rpt_status=0
        pre-commit run --verbose --color "$_rpt_color" "$@" || _rpt_status=$?
        printf '%s\n' "$_rpt_status" > "$_rpt_log.status"
    } | tee "$_rpt_log" | precommit_display_filter
    _rpt_status=$(cat "$_rpt_log.status" 2> /dev/null)
    rm -f "$_rpt_log.status"
    [ "$_rpt_status" = "0" ]
}
