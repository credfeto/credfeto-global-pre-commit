#!/usr/bin/env bats
# Acceptance tests for src/scripts/lib/dotnet-sdk-check.sh's
# require_compatible_dotnet_sdk() helper, which buildtest and buildcheck call
# before any other `dotnet` invocation so a global.json SDK feature-band
# mismatch fails fast with an unambiguous message instead of being
# misdiagnosed later as a missing dotnet tool (require_dotnet_tool's "is not
# installed" message -- this helper's message must never be confused with
# it). Invoked by sourcing the lib directly with a fake `dotnet` on PATH --
# no real SDK mismatch or dotnet install required.

load test_helper

LIB="${REPO_DIR}/src/scripts/lib/dotnet-sdk-check.sh"

# Writes a fake `dotnet` executable to "$1/dotnet" whose --version resolves
# successfully (exit 0), matching the working-SDK-band case.
write_good_dotnet() {
    local _dir="$1"
    mkdir -p "${_dir}"
    cat > "${_dir}/dotnet" <<'EOF'
#!/bin/sh
case "$1" in
    --version)
        echo "10.0.400"
        exit 0
        ;;
    --list-sdks)
        printf '10.0.400 [/usr/share/dotnet/sdk]\n'
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "${_dir}/dotnet"
}

# Writes a fake `dotnet` executable to "$1/dotnet" that succeeds for
# --list-sdks (printing a canned installed-SDK list, bypassing global.json
# resolution like the real dotnet does) but exits 155 with the real-world
# exit-155 SDK-resolution error text for --version (or anything else).
write_bad_dotnet() {
    local _dir="$1"
    mkdir -p "${_dir}"
    cat > "${_dir}/dotnet" <<'EOF'
#!/bin/sh
case "$1" in
    --list-sdks)
        printf '9.0.317 [/usr/share/dotnet/sdk]\n10.0.400 [/usr/share/dotnet/sdk]\n'
        exit 0
        ;;
    *)
        echo "A compatible .NET SDK was not found." >&2
        echo "Requested SDK version: 10.0.302" >&2
        echo "global.json file: /workspace/repo/src/global.json" >&2
        exit 155
        ;;
esac
EOF
    chmod +x "${_dir}/dotnet"
}

@test "require_compatible_dotnet_sdk returns 0 with no output when the SDK resolves" {
    local _fake="${BATS_TEST_TMPDIR}/good-dotnet"
    write_good_dotnet "${_fake}"
    # shellcheck disable=SC2016 # intentionally literal — expanded by the inner sh, not here
    run env PATH="${_fake}:${TEST_PATH}" sh -c '
        die() { printf "DIED: %s\n" "$*"; exit 1; }
        . "$1"
        require_compatible_dotnet_sdk
    ' _ "${LIB}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "require_compatible_dotnet_sdk dies with the SDK-band mismatch details, not a missing-tool message" {
    local _fake="${BATS_TEST_TMPDIR}/bad-dotnet"
    write_bad_dotnet "${_fake}"
    # shellcheck disable=SC2016 # intentionally literal — expanded by the inner sh, not here
    run env PATH="${_fake}:${TEST_PATH}" sh -c '
        die() { printf "DIED: %s\n" "$*"; exit 1; }
        . "$1"
        require_compatible_dotnet_sdk
    ' _ "${LIB}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Requested SDK version: 10.0.302"* ]]
    [[ "${output}" == *"10.0.400 [/usr/share/dotnet/sdk]"* ]]
    [[ "${output}" != *"is not installed"* ]]
}
