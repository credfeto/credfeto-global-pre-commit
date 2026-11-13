#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

# ── ansible-lint ──────────────────────────────────────────────────────────────

_ansible_env_ok() {
    local _probe_dir _probe_out
    _probe_dir="$(mktemp -d)"
    _probe_out="$(ansible-lint --nocolor "${_probe_dir}" 2>&1 || true)"
    rm -rf "${_probe_dir}"
    if printf '%s' "${_probe_out}" | grep -qi "do not match\|broken execution"; then
        return 1
    fi
    return 0
}

@test "broken Ansible playbook (yaml[truthy] violation) is rejected" {
    if ! command -v ansible-lint > /dev/null 2>&1; then
        skip "ansible-lint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! _ansible_env_ok; then
        skip "ansible-lint environment broken (version mismatch)"
    fi
    local T
    T="$(make_repo feature/broken-playbook-test)"
    printf 'repos:\n  - repo: local\n    hooks:\n      - id: ansible-lint\n        name: ansible-lint\n        entry: ansible-lint -v --force-color --exclude .github\n        language: system\n        pass_filenames: false\n        always_run: true\n' > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' '- name: Broken playbook' '  hosts: localhost' '  gather_facts: yes' '  tasks:' '    - name: Hello world' '      ansible.builtin.debug:' '        msg: Hello' > "${T}/broken.yml"
    git -C "${T}" add .pre-commit-config.yaml broken.yml
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "valid Ansible playbook passes" {
    if ! command -v ansible-lint > /dev/null 2>&1; then
        skip "ansible-lint not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    if ! _ansible_env_ok; then
        skip "ansible-lint environment broken (version mismatch)"
    fi
    local T
    T="$(make_repo feature/valid-playbook-test)"
    printf 'repos:\n  - repo: local\n    hooks:\n      - id: ansible-lint\n        name: ansible-lint\n        entry: ansible-lint -v --force-color --exclude .github\n        language: system\n        pass_filenames: false\n        always_run: true\n' > "${T}/.pre-commit-config.yaml"
    printf '%s\n' '---' '- name: Valid test playbook' '  hosts: all' '  gather_facts: false' '  tasks:' '    - name: Print hello' '      ansible.builtin.debug:' '        msg: Hello World' > "${T}/clean.yml"
    git -C "${T}" add .pre-commit-config.yaml clean.yml
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
