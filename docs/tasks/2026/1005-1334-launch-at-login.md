---
status: completed
pipeline_phase: null
plan: null
base_ref: null
perspectives: [completeness, clarity, user-experience]
max_refine_rounds: 3
retries_remaining: 1
check_command: "make build && make test && make app && grep -rq 'SMAppService' Sources/SuttoInfra/ && ! grep -rq 'ServiceManagement' Sources/SuttoDomain/ Sources/SuttoOperations/ Sources/SuttoUI/ && grep -rq 'LaunchAtLogin' Tests/SuttoOperationsTests/ && grep -rq 'LaunchAtLogin' Tests/SuttoDomainTests/ && grep -q 'case general' Sources/SuttoUI/SettingsTab.swift && grep -qi 'login' README.md"
assignee: null
branch: task/1005-1334-launch-at-login
created_at: 2026-10-05T13:34:15Z
updated_at: 2026-10-05T14:05:50Z
---

# feat(settings): add a Launch at Login toggle backed by SMAppService

## Overview

Sutto is a menu bar accessory app that is meant to stay resident, but nothing
relaunches it after a logout or reboot. Launching at login via `SMAppService`
was never implemented: a grep for `SMAppService` / `LoginItem` /
`LaunchAgent` over `Sources/` finds nothing, and in practice, after a macOS
update's reboot the app was simply gone until started by hand. The GNOME version has no
equivalent because a Shell extension loads with the Shell; this is macOS-only.

Implement the macOS-conventional shape: the app offers a **"Launch Sutto at
login"** toggle in its settings and registers itself through
`SMAppService.mainApp` (ServiceManagement, macOS 13+; the package already
requires 14). The OS then lists the app under System Settings › General › Login
Items & Extensions, where the user can also turn it off. Do **not** use a
LaunchAgent plist, `LSSharedFileList`, or the helper-based
`SMLoginItemSetEnabled` — all are either non-conventional for GUI apps or
deprecated.

### Behaviour

- **Opt-in, default off.** Never register at first launch without the user
  asking: registering fires the OS "added as a login item" notice, and a
  background item the user did not ask for is the kind of surprise this app
  avoids elsewhere (see the non-blocking edge-tiling guidance). The toggle is
  the only way in.
- **The OS is the source of truth.** Do not persist an "enabled" preference of
  our own. Read `SMAppService.mainApp.status` fresh every time the pane is
  refreshed (`SettingsWindowController.refresh()` already re-reads every pane on
  present), so the checkbox reflects reality if the user disabled the item in
  System Settings, and nothing can drift between a stored flag and launchd.
- **Status mapping**, as a domain value type (Foundation-only, unit-tested),
  mirroring how `LicensePresentation` keeps wording out of the view:
  - `.enabled` → checkbox on.
  - `.notRegistered` → checkbox off.
  - `.requiresApproval` → checkbox on but the item is blocked by the user in
    System Settings; show a hint under the checkbox saying approval is needed
    there and a button that opens the Login Items pane
    (`SMAppService.openSystemSettingsLoginItems()`, called through the infra
    adapter — the UI layer never imports ServiceManagement).
  - `.notFound` → treat as off (the registration points at a bundle that no
    longer exists; toggling on re-registers the current bundle).
- **Toggle on** calls `register()`; **toggle off** calls `unregister()`. Both
  throw; on failure, revert the checkbox to the real status and show an
  `NSAlert` in the style of `ShortcutsSettingsPane.presentFailure` (what
  happened, that the previous state stays). Log the error with the
  `io.github.x7c1.SuttoMac` subsystem like the other adapters.
- Operation × state coverage for the toggle: enumerate the four
  `SMAppService.Status` cases as the states the target can be in when the
  user flips the switch, and cover each in the use-case tests (criteria
  below). Out of scope: registering helper tools, agents, or daemons — only
  `.mainApp`.

### Where it lives (layering per docs/guides/architecture.md)

- **SuttoDomain**: a `LaunchAtLoginStatus` (or similarly named) value type
  with the four cases, the derived `isEnabled` / `needsApproval` booleans, and
  the user-facing hint text for the approval case. Tested in
  `Tests/SuttoDomainTests`.
- **SuttoOperations**: a `LoginItemRegistering` protocol (current status,
  register, unregister, open the Login Items settings pane) and a
  `LaunchAtLoginUseCase` the pane calls (`currentStatus()`,
  `setEnabled(_:) throws`). Tested in `Tests/SuttoOperationsTests` with an
  in-test stub registrar, like the other use-case tests.
- **SuttoInfra**: `SMAppServiceLoginItemRegistrar` implementing the protocol
  over `SMAppService.mainApp`. Not unit-tested (it talks to launchd); the
  manual criteria cover it. Note `SMAppService` is `@MainActor`-agnostic but
  the use case is called from the main thread only; keep the protocol
  `@MainActor` if that is what the compiler needs.
- **SuttoUI**: a new `SettingsTab.general` case placed **first** in toolbar
  order (the macOS convention for a General tab; SF Symbol `gearshape`), with a
  `GeneralSettingsPane` holding the checkbox, the approval hint, and the
  button. Follow `ShortcutsSettingsPane` for construction (state views built
  in `init`, `refresh()` safe before `loadView`, `SettingsPane.containerView`
  for margins, `SettingsMetrics` / `SettingsTypography` tokens). Keep
  `SettingsTab.restored()` defaulting to `.layouts` — the existing comment
  gives the reason (parity with where the GNOME preferences open) and a user
  who has never picked a tab should still land on the primary surface. Wire
  `refresh()` into `SettingsWindowController.refresh()` and the pane into
  `makePane(for:)`; the doc comments on `SettingsTab` and `makePane` that
  use "a future License tab" as their example are now stale (License exists)
  — update them to point at General or drop the example.
- **SuttoApp**: construct the infra registrar in `AppDelegate`, build the use
  case, and pass it into `SettingsWindowController.init` alongside the other
  use cases. Wiring only.

### Documentation

- `README.md`: in the section that explains the menu bar / Accessibility
  behaviour, add a short paragraph: launch at login is opt-in from Settings ›
  General, and it registers **the bundle that is running**. For a development
  build that is `.build/Sutto.app`, which `make app` recreates at the same
  path (so the registration survives rebuilds) but `make clean` removes (so
  login launch silently fails until the next `make app`). Point at the
  debugging guide if the detail grows beyond a paragraph. Keep in mind an
  unsigned rebuilt bundle is "a new app" for TCC; say whether the login item
  survives that in the same breath as the existing Accessibility note (the
  manual criteria establish the answer — write what was observed, not a
  guess).

## Acceptance criteria

### Automated (pipeline-verified)

- [x] `Sources/SuttoInfra/` contains the `SMAppService`-backed registrar, and
      `ServiceManagement` is imported nowhere in `SuttoDomain`,
      `SuttoOperations`, or `SuttoUI` (both greps are gates in
      `check_command`, so the layering is enforced, not just intended).
- [x] `Sources/SuttoUI/SettingsTab.swift` gains `case general` and the app
      still builds and assembles a bundle (`make build && make app`).
- [x] `Tests/SuttoDomainTests` covers the status value type: each of the four
      cases maps to the expected `isEnabled` / `needsApproval` pair, and only
      the approval case yields hint text.
- [x] `Tests/SuttoOperationsTests` covers the use case with a stub registrar
      across the operation × state matrix: enabling from `.notRegistered` and
      from `.notFound` calls `register`; enabling from `.enabled` and from
      `.requiresApproval` is a no-op (no second register); disabling from
      `.enabled` and from `.requiresApproval` calls `unregister`; disabling
      from `.notRegistered` / `.notFound` is a no-op; a throwing registrar
      propagates the error and `currentStatus()` afterwards still reports the
      stub's real status (no cached flag).
- [x] `README.md` documents the opt-in toggle and the development-bundle
      caveat (gate: `grep -qi 'login' README.md`).

### Manual / on-hardware (verified by a human before merge)

- [ ] On a real Mac, turning the toggle on makes Sutto appear under
      System Settings › General › Login Items & Extensions, and Sutto is
      running in the menu bar after a logout/login (or reboot) without being
      started by hand.
- [ ] Turning the item off in System Settings (not in Sutto) and reopening
      Sutto's Settings shows the checkbox off — the pane reads the OS state.
- [ ] Toggling off in Sutto removes the item from System Settings, and after
      the next login Sutto is not running.
- [ ] After `make run` rebuilds the unsigned bundle, the login item either
      still launches it or does not; whichever was observed is what the README
      states.

