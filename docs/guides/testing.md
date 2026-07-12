# Testing

## Overview

Sutto for macOS keeps its test suite in two tiers. Unit tests cover the
`SuttoDomain` and `SuttoOperations` targets and run everywhere, including CI.
End-to-end tests that actually move or resize real windows require the
Accessibility (TCC) permission, which cannot be granted in CI, so they are
local-only; CI runs unit tests exclusively.

## Running tests: why `make test` instead of `swift test`

On machines with only the Xcode Command Line Tools (no full Xcode), the
toolchain ships Testing.framework but SwiftPM does not wire it up on its own,
so a bare `swift test` fails to find Swift Testing. The Makefile detects this
setup and conditionally injects the required compiler, macro-plugin, linker,
and rpath flags (`SWIFT_TEST_FLAGS`) pointing at the CLT copies.

With a full Xcode toolchain the flags stay empty and `make test` degrades to
plain `swift test`. Always use `make test` so the same command works in both
environments.

## Unit tests and stubs

Unit tests in `Tests/SuttoOperationsTests` exercise the use cases by
substituting the protocols that `SuttoOperations` defines (and `SuttoInfra`
normally implements) with small in-test stubs — for example, a
`PermissionChecking` stub with a scriptable status stands in for the AX-backed
checker. No Accessibility APIs or AppKit are involved, which is what lets
these tests run unprivileged in CI.
