#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

# Own scoped config for the run-pylint wrapper tests below (entry: run-pylint
# rather than entry: pylint), per linters.instructions.md's "own scoped
# config" rule — these exercise the wrapper's venv/manifest handling, not
# pylint itself, and must not be masked by PYLINT_CONFIG's direct entry.
PYLINT_WRAPPER_CONFIG='repos:
  - repo: local
    hooks:
      - id: pylint
        name: pylint
        entry: run-pylint
        language: system
        types: [python]
'

# ── run-pylint wrapper (repo-declared dependency resolution) ───────────────────

# Matches VENV_DIR in src/scripts/run-pylint.
PYLINT_VENV_DIR="credfeto-precommit-pylint-venv"

# python3 -m venv is slow enough, and needed by 4 tests below, that the
# probe's pass/fail verdict is cached to disk for the run (BATS_RUN_TMPDIR is
# shared across the whole run) rather than rebuilt from scratch every call.
# Guarded by the same _run_once_value helper as the GPG key/trivy DB warm-ups
# in test_helper.bash: bats 1.10.x doesn't reset BATS_TEST_TMPDIR between
# tests in the same file, so two tests racing the check-then-create sequence
# under bats --jobs could otherwise collide on the same probe directory, not
# just the cache file.
_probe_venv_functional() {
    local _cache="$1" _probe="${BATS_TEST_TMPDIR}/venvprobe" _result=0
    python3 -m venv --system-site-packages "${_probe}" > /dev/null 2>&1 || _result=1
    rm -rf "${_probe}"
    echo "${_result}" > "${_cache}"
}

_venv_functional_ok() {
    local _cache="${BATS_RUN_TMPDIR}/venv-functional-ok"
    [ "$(_run_once_value "${_cache}" _probe_venv_functional "${_cache}")" = "0" ]
}

_require_functional_venv() {
    if ! _venv_functional_ok; then
        skip "python3 -m venv is not functional in this environment (install python3-venv)"
    fi
}

# Writes a good.py that imports/uses six, the shared probe module used to
# prove a declared dependency is actually resolvable from the venv.
_write_six_probe_module() {
    printf '"""Uses six."""\n\nimport six\n\nprint(six.__version__)\n' > "$1/good.py"
}

# Writes a requirements.txt + good.py pair declaring/using six, the shared
# fixture dependency for the venv-caching tests below.
_write_six_fixture() {
    printf 'six==1.16.0\n' > "$1/requirements.txt"
    _write_six_probe_module "$1"
}

# Per-test XDG_CACHE_HOME for the tests below whose run-pylint venv really
# pip-installs a declared dependency: pip's cache lives under it, and sharing
# the host's one cache directory across concurrent pip installs under
# bats --jobs made those installs race. Removed by teardown so a failed
# assertion cannot leak it.
PIP_TEST_CACHE=""

teardown() {
    if [ -n "${PIP_TEST_CACHE}" ]; then
        rm -rf "${PIP_TEST_CACHE}"
    fi
}

_run_hook_with_isolated_pip_cache() {
    run_hook_env "$1" "${TEST_PATH}" "${PIP_TEST_CACHE}"
}

# Asserts pylint ran directly against $3 with no venv left behind and
# rejected the undefined-variable fixture, shared by the "no venv built"
# tests below. Takes $status/$output as $1/$2 rather than reading the bats
# globals directly, so shellcheck can see they stay within the @test's own
# subshell.
_assert_ran_without_venv() {
    [ "$1" -eq 1 ]
    [[ "$2" == *"E0602"* ]]
    [ ! -d "$3/.git/${PYLINT_VENV_DIR}" ]
}

@test "run-pylint wrapper behaves like plain pylint when the repo declares no dependency manifest" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/pylint-wrapper-no-manifest)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'def bad():\n    print(undefined_var)\n' > "${T}/bad.py"
    git -C "${T}" add .pre-commit-config.yaml bad.py
    run_hook "${T}"
    _assert_ran_without_venv "${status}" "${output}" "${T}"
}

@test "run-pylint wrapper does not build a venv for a pyproject.toml with no [project.dependencies]" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/pylint-wrapper-pyproject-no-deps)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    cat > "${T}/pyproject.toml" <<'EOF'
[tool.black]
line-length = 100
EOF
    printf 'def bad():\n    print(undefined_var)\n' > "${T}/bad.py"
    git -C "${T}" add .pre-commit-config.yaml pyproject.toml bad.py
    run_hook "${T}"
    _assert_ran_without_venv "${status}" "${output}" "${T}"
}

@test "run-pylint wrapper falls back to system pylint when a declared dependency cannot be installed" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/pylint-wrapper-install-fail)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    printf 'this-package-definitely-does-not-exist-nonexistent-xyz123==0.0.0\n' > "${T}/requirements.txt"
    printf 'def bad():\n    print(undefined_var)\n' > "${T}/bad.py"
    git -C "${T}" add .pre-commit-config.yaml requirements.txt bad.py
    run_hook "${T}"
    [[ "${output}" == *"warning: run-pylint:"* ]]
    _assert_ran_without_venv "${status}" "${output}" "${T}"
}

@test "run-pylint wrapper installs requirements.txt dependencies into a cached venv so pylint resolves the import" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    _require_functional_venv
    PIP_TEST_CACHE="$(mktemp -d)"
    T="$(make_repo feature/pylint-wrapper-reqs)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    _write_six_fixture "${T}"
    git -C "${T}" add .pre-commit-config.yaml requirements.txt good.py
    _run_hook_with_isolated_pip_cache "${T}"
    [ "${status}" -eq 0 ]
    [ -x "${T}/.git/${PYLINT_VENV_DIR}/bin/python3" ]
}

@test "run-pylint wrapper reuses the cached venv when requirements.txt is unchanged" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T _venv_python _inode_before _inode_after
    _require_functional_venv
    PIP_TEST_CACHE="$(mktemp -d)"
    T="$(make_repo feature/pylint-wrapper-reqs-cache)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    _write_six_fixture "${T}"
    git -C "${T}" add .pre-commit-config.yaml requirements.txt good.py
    _run_hook_with_isolated_pip_cache "${T}"
    [ "${status}" -eq 0 ]
    _venv_python="${T}/.git/${PYLINT_VENV_DIR}/bin/python3"
    _inode_before="$(stat -c %i "${_venv_python}")"
    _run_hook_with_isolated_pip_cache "${T}"
    [ "${status}" -eq 0 ]
    _inode_after="$(stat -c %i "${_venv_python}")"
    [ "${_inode_before}" = "${_inode_after}" ]
}

@test "run-pylint wrapper rebuilds the venv when requirements.txt changes" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T _venv_python _stamp _hash_after
    _require_functional_venv
    PIP_TEST_CACHE="$(mktemp -d)"
    T="$(make_repo feature/pylint-wrapper-reqs-rebuild)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    _write_six_fixture "${T}"
    git -C "${T}" add .pre-commit-config.yaml requirements.txt good.py
    _run_hook_with_isolated_pip_cache "${T}"
    [ "${status}" -eq 0 ]
    _venv_python="${T}/.git/${PYLINT_VENV_DIR}/bin/python3"
    _stamp="${T}/.git/${PYLINT_VENV_DIR}/.requirements-hash"
    # The venv is not yet layered with cowsay. Deliberately not certifi/requests
    # or another networking-adjacent package: GitHub Actions' Ubuntu runner
    # image and ansible-lint's apt dependency chain already pull those into
    # system site-packages, which a --system-site-packages venv inherits
    # regardless of whether this wrapper ever installed them (seen in CI as a
    # false failure of the "not yet layered" assertion below). cowsay has no
    # legitimate reason to be a transitive dependency of anything on the
    # runner, so its absence/presence actually reflects this wrapper's own
    # install step.
    run "${_venv_python}" -c 'import cowsay'
    [ "${status}" -ne 0 ]
    printf 'six==1.16.0\ncowsay\n' > "${T}/requirements.txt"
    git -C "${T}" add requirements.txt
    _run_hook_with_isolated_pip_cache "${T}"
    [ "${status}" -eq 0 ]
    # A rebuild is proven behaviourally (the newly-declared dependency is now
    # importable from the venv) rather than via inode identity, which is not a
    # reliable rebuild signal: rm -rf followed immediately by re-creation can
    # have the filesystem reuse the just-freed inode number for the new file.
    run "${_venv_python}" -c 'import cowsay'
    [ "${status}" -eq 0 ]
    _hash_after="$(sha256sum "${T}/requirements.txt" | cut -d' ' -f1)"
    [ "$(cat "${_stamp}")" = "${_hash_after}" ]
}

@test "run-pylint wrapper installs pyproject.toml [project.dependencies] into a cached venv so pylint resolves the import" {
    if ! command -v pylint > /dev/null 2>&1; then
        skip "pylint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    _require_functional_venv
    PIP_TEST_CACHE="$(mktemp -d)"
    T="$(make_repo feature/pylint-wrapper-pyproject-deps)"
    printf '%s' "${PYLINT_WRAPPER_CONFIG}" > "${T}/.pre-commit-config.yaml"
    cat > "${T}/pyproject.toml" <<'EOF'
[project]
name = "wrapper-test"
version = "0.0.1"
dependencies = [
    "six==1.16.0",
]
EOF
    _write_six_probe_module "${T}"
    git -C "${T}" add .pre-commit-config.yaml pyproject.toml good.py
    _run_hook_with_isolated_pip_cache "${T}"
    [ "${status}" -eq 0 ]
    [ -x "${T}/.git/${PYLINT_VENV_DIR}/bin/python3" ]
}
