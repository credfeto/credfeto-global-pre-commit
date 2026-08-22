#! /bin/sh
# Shared helper sourced by buildtest and buildcheck. Not intended to be run directly.
#
# require_compatible_dotnet_sdk() fails fast and unambiguously when the current
# directory's global.json pins a .NET SDK feature band that isn't installed in
# this environment, instead of letting a later `dotnet` call fail in a way that
# gets misdiagnosed as a missing dotnet tool (credfeto/credfeto-global-pre-commit#213).
# Depends on the caller already defining die().

# `dotnet --version` resolves global.json in the current directory and fails
# outright (no fallback) when the pinned SDK band isn't installed; `dotnet
# --list-sdks` bypasses global.json resolution entirely and always succeeds,
# so it is safe to call unconditionally to report what is actually installed.
require_compatible_dotnet_sdk() {
    if _dotnet_sdk_check_output=$(dotnet --version 2>&1); then
        return 0
    fi

    _dotnet_sdk_check_installed=$(dotnet --list-sdks 2>&1)
    die "$(printf '%s\n\nInstalled SDKs:\n%s\n\nThis is a .NET SDK feature-band mismatch between global.json and the environment (not a missing dotnet tool) - the image needs an SDK install matching global.json, or global.json needs updating to a band that is installed.' \
        "$_dotnet_sdk_check_output" "$_dotnet_sdk_check_installed")"
}
