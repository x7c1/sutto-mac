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

## End-to-end tests

`Tests/SuttoE2ETests` drives the real app from the outside, the way a user
would: it launches the freshly assembled `Sutto.app` bundle, injects the
global shortcut with `CGEventPost`, presses a layout button on the panel
through the Accessibility API, and asserts that a real window landed exactly
on the frame the domain resolver predicts. The window being snapped is a
private helper app (`Tests/SuttoE2ETargetApp`) rather than a system app like
TextEdit, whose launch state is not deterministic (restored documents, the
iCloud open panel) and whose windows may hold a developer's real work.

### Running

```sh
make e2e
```

`make e2e` assembles the bundle first (it depends on the `app` target), then
runs only the e2e module. The split between the two suites lives in the
Makefile: `make test` passes `--skip SuttoE2ETests` and `make e2e` passes
`--filter SuttoE2ETests`. Both flags match test identifiers, which start with
the module name, so the split holds no matter what tests are added on either
side.

The run takes a few seconds of real screen time: a small "Sutto E2E Target"
window opens, the layout panel flashes, and the window snaps to the left half
of the work area. Every process the suite starts is terminated when the test
ends (including in teardown after a failure). Run it on a momentarily idle
desktop — the suite forces its helper window to the front, and it also quits
any Sutto instance that is already running (say, from `make run`), because
two instances would race for the global shortcut.

### Granting the Accessibility permission (first run)

The suite checks the permission up front and fails with instructions when it
is missing. Grant Accessibility to the application you run `make e2e` from —
your terminal app, or the editor hosting the integrated terminal — under
System Settings › Privacy & Security › Accessibility.

That one grant is enough, by construction: the suite launches Sutto and the
helper with `Process` (plain fork/exec), which keeps the terminal the TCC
*responsible process* for the whole process tree. The test runner's event
injection and the spawned Sutto's AX calls are all attributed to the
terminal, and the grant survives rebuilds without any code signing. (A Sutto
launched via `make run`/`open` is its own responsible process and needs its
own grant; the `CODESIGN_IDENTITY` tip in
[debugging.md](debugging.md#keeping-the-accessibility-permission-across-rebuilds)
keeps *that* grant stable across rebuilds. The e2e path does not depend on
it.)

### Local-only by design

CI (GitHub Actions, [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml))
runs `make test` and must never execute the e2e suite: granting a TCC
permission requires an interactive, trusted UI session that CI runners do not
have. That criterion is unchanged by the harness existing — the e2e suite is
promoted to CI only if that constraint ever falls (for example, a supported
way to pre-authorize Accessibility on ephemeral runners), not by making the
tests themselves less demanding.
