#!/usr/bin/env bats
# Linter-specific acceptance tests.  Each linter pair verifies that an invalid
# file causes the hook to exit non-zero and a valid file allows it to pass.
# Tests for unavailable tools emit a SKIP message and return early.

load test_helper

# Warms trivy's vulnerability DB once for the whole file (not per-test) so
# every trivy-invoking test here, present or future, is covered automatically
# rather than relying on each test remembering to call ensure_trivy_db_warm.
# Skipped when pre-commit is absent, matching the trivy tests' own guard below
# (both are required for those tests to run at all) so a trivy-only host
# doesn't pay for a DB download whose only consumers will skip anyway.
setup_file() {
    command -v pre-commit > /dev/null 2>&1 && ensure_trivy_db_warm
    return 0
}

TRIVY_CONFIG='repos:
  - repo: local
    hooks:
      - id: trivy
        name: trivy (dependency vulnerabilities)
        entry: trivy fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --quiet .
        language: system
        pass_filenames: false
        files: (^|/)(package-lock\.json|packages\.lock\.json|go\.sum|requirements[^/]*\.txt|Gemfile\.lock|poetry\.lock|Pipfile\.lock)$
'

# ── trivy ────────────────────────────────────────────────────────────────────

@test "package-lock.json with known-vulnerable dependency is rejected" {
    if ! command -v trivy > /dev/null 2>&1; then
        skip "trivy not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/vulnerable-lockfile-test)"
    printf '%s' "${TRIVY_CONFIG}" > "${T}/.pre-commit-config.yaml"
    cat > "${T}/package-lock.json" <<'EOF'
{
  "name": "test",
  "version": "1.0.0",
  "lockfileVersion": 2,
  "requires": true,
  "packages": {
    "": {
      "name": "test",
      "version": "1.0.0",
      "dependencies": {
        "lodash": "4.17.15"
      }
    },
    "node_modules/lodash": {
      "version": "4.17.15",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.15.tgz",
      "integrity": "sha512-8xOcRHvCjnocdS5cpwXQXVzmmh5e5+saE2QGoeQmbKmRS6J3VQppPOIt0MnmE+4xlZoumy0GPG0D0MVIQbNA1A=="
    }
  },
  "dependencies": {
    "lodash": {
      "version": "4.17.15",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.15.tgz",
      "integrity": "sha512-8xOcRHvCjnocdS5cpwXQXVzmmh5e5+saE2QGoeQmbKmRS6J3VQppPOIt0MnmE+4xlZoumy0GPG0D0MVIQbNA1A=="
    }
  }
}
EOF
    git -C "${T}" add .pre-commit-config.yaml package-lock.json
    run_hook "${T}"
    [ "${status}" -eq 1 ]
}

@test "package-lock.json with no third-party dependencies passes trivy" {
    if ! command -v trivy > /dev/null 2>&1; then
        skip "trivy not installed"
    fi
    if ! command -v pre-commit > /dev/null 2>&1; then
        skip "pre-commit not installed"
    fi
    local T
    T="$(make_repo feature/clean-lockfile-test)"
    printf '%s' "${TRIVY_CONFIG}" > "${T}/.pre-commit-config.yaml"
    # No third-party packages, so there is nothing for the vulnerability
    # database to ever flag — unlike pinning a real package version, this
    # can't be broken by a future CVE being published against it.
    cat > "${T}/package-lock.json" <<'EOF'
{
  "name": "test",
  "version": "1.0.0",
  "lockfileVersion": 2,
  "requires": true,
  "packages": {
    "": {
      "name": "test",
      "version": "1.0.0"
    }
  },
  "dependencies": {}
}
EOF
    git -C "${T}" add .pre-commit-config.yaml package-lock.json
    run_hook "${T}"
    [ "${status}" -eq 0 ]
}
