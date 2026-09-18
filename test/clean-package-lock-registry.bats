#!/usr/bin/env bats
# Acceptance tests for src/scripts/clean-package-lock-registry: normalises a
# private npm registry URL in package-lock.json back to the public registry
# and re-stages the fix.

load test_helper

bats_require_minimum_version 1.5.0

SCRIPT="${REPO_DIR}/src/scripts/clean-package-lock-registry"

PRIVATE_LOCK='{
  "name": "example",
  "resolved": "https://npm.markridgwell.com/example/-/example-1.0.0.tgz"
}
'

@test "normalises a staged package-lock.json and re-stages it" {
    local T
    T="$(make_repo feature/clean-lock-staged-test)"
    printf '%s' "${PRIVATE_LOCK}" > "${T}/package-lock.json"
    git -C "${T}" add package-lock.json

    cd "${T}"
    run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    grep -q "registry.npmjs.org" "${T}/package-lock.json"
    run ! grep -q "npm.markridgwell.com" "${T}/package-lock.json"
    run git -C "${T}" diff --cached --name-only
    [[ "${output}" == *"package-lock.json"* ]]
}

@test "default mode skips a tracked but unstaged package-lock.json" {
    local T
    T="$(make_repo feature/clean-lock-default-skips-test)"
    printf '%s' "${PRIVATE_LOCK}" > "${T}/package-lock.json"
    git -C "${T}" add package-lock.json
    git -C "${T}" commit --quiet --no-verify -m seed

    cd "${T}"
    run "${SCRIPT}"

    [ "${status}" -eq 0 ]
    grep -q "npm.markridgwell.com" "${T}/package-lock.json"
}

@test "all-files mode normalises and stages a tracked but unstaged package-lock.json" {
    local T
    T="$(make_repo feature/clean-lock-allfiles-test)"
    printf '%s' "${PRIVATE_LOCK}" > "${T}/package-lock.json"
    git -C "${T}" add package-lock.json
    git -C "${T}" commit --quiet --no-verify -m seed

    cd "${T}"
    run "${SCRIPT}" --all-files

    [ "${status}" -eq 0 ]
    grep -q "registry.npmjs.org" "${T}/package-lock.json"
    run ! grep -q "npm.markridgwell.com" "${T}/package-lock.json"
    run git -C "${T}" diff --cached --name-only
    [[ "${output}" == *"package-lock.json"* ]]
}

@test "clean-package-lock-registry rejects an unknown argument" {
    local T
    T="$(make_repo feature/clean-lock-unknown-arg-test)"
    cd "${T}"
    run "${SCRIPT}" --bogus
    [ "${status}" -eq 1 ]
}
