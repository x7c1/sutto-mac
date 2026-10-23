---
status: completed
pipeline_phase: null
plan: null
base_ref: null
perspectives: [completeness, clarity, user-experience]
max_refine_rounds: 3
retries_remaining: 1
check_command: "make build && make test && make app && grep -rq 'trial-expired' Sources/SuttoDomain/ && grep -rq 'trialExpired' Tests/SuttoOperationsTests/ && grep -rq 'trialExpired' Tests/SuttoInfraTests/ && ! grep -rq 'recordTrialUsageOnLaunch' Sources/ Tests/"
assignee: null
branch: task/1023-1840-trial-expired-status
created_at: 2026-10-23T09:40:50Z
updated_at: 2026-10-23T09:57:23Z
---

# feat(licensing): make trial expiry its own status and count trial days on panel show

## Overview

The license gate contract shared with the GNOME version (x7c1/sutto) has five
license statuses: `trial`, `trial-expired`, `valid`, `expired`, `invalid`.
`expired` and `invalid` are reserved for licenses the backend authoritatively
refused. The macOS version still has four: when the 30-day trial is spent,
`LicenseGate.recordTrialUsageOnLaunch()`
(`Sources/SuttoOperations/Licensing/LicenseGate.swift`) writes `.expired`, and
`LicensePresentation.statusText` tells the two apart by whether a record
exists. A later change makes a spent trial reopen when the backend does not
answer, while an authoritatively expired license stays closed, so the two
must be distinguishable from the status alone. This task does that and also
changes when trial days are counted. The GNOME version already implements
both; use it as the reference (`src/domain/licensing/license-status.ts`,
`src/operations/licensing/license-operations.ts` in x7c1/sutto).

1. **New status.** Add `LicenseStatus.trialExpired` with raw value
   `"trial-expired"` (`Sources/SuttoDomain/Licensing/LicenseStatus.swift`).
   The `trial` → `trialExpired` transition happens in exactly one place: when
   recording a usage day brings the trial to 30 days. `clearLicense()` on a
   spent trial yields `trialExpired`, not `expired`. `LicenseGatePolicy`
   keeps `trialExpired` closed for now (the reachability probe that may
   reopen it is a separate task). Update the doc comments on `LicenseStatus`,
   `LicenseState.status`, and `LicenseGatePolicy` to the five-value model.
2. **Count days on panel show, not at launch.** A usage day is counted when a
   normal panel is actually shown, whichever entry point showed it (shortcut,
   status menu, edge trigger). A show refused by a closed gate is not
   counted. At most one day per calendar day, regardless of the backend.
   Nothing is counted at launch: remove `recordTrialUsageOnLaunch()` and its
   call in the launch pass in `Sources/SuttoApp/AppDelegate.swift`, and
   update the launch-pass comment there. Keep the counting logic in
   `LicenseGate` (Operations) and have the panel-show seams in
   `PanelToggleUseCase` and `EdgeTriggerUseCase` (or their wiring in
   `AppDelegate`) call it only on the branch that shows the panel. The panel
   that records day 30 is still shown; the next show is refused.
3. **Read legacy files.** A stored status `expired` with no license record
   (no key) is a spent trial that the old code wrote as `expired`. Load it as
   `trialExpired` (`Sources/SuttoInfra/Licensing/FileLicenseRepository.swift`,
   where the document is mapped to `LicenseState`). A stored `expired` with a
   record stays `expired`.
4. **Wording.** `LicensePresentation.statusText` gets a `trialExpired` case
   with the current spent-trial text ("Trial expired — activate a license to
   keep using Sutto"), and the `expired` case keeps only the license wording.
   Check the status menu and the License settings pane for other places that
   inferred a spent trial from `expired` + no record.

Operation × state coverage for "show the panel" (each needs an Operations
test):

- `trial`, today not yet counted → day counted, panel shown
- `trial`, today already counted → not counted, panel shown
- `trial` at 29 days, today not counted → counted, becomes `trialExpired`,
  panel shown; the next show is refused and not counted
- `trialExpired`, `valid`, `expired`, `invalid` → not counted
- gate closed → panel not shown, not counted

Out of scope: the remaining-days warnings the GNOME version shows (the macOS
version has none yet), the reachability probe for a spent trial, and the
7-day offline limit. Each is a separate task.

## Acceptance criteria

### Automated (pipeline-verified)

- [x] `LicenseStatus` has a `trialExpired` case whose raw value is
      `"trial-expired"`, and `LicenseGatePolicy` keeps it closed
      (`grep -rq 'trial-expired' Sources/SuttoDomain/` in `check_command`, plus
      a Domain test).
- [x] A trial reaching 30 days becomes `trialExpired`, never `expired`, and
      `clearLicense()` on a spent trial yields `trialExpired` (Operations
      tests that mention `trialExpired`, gated by
      `grep -rq 'trialExpired' Tests/SuttoOperationsTests/`).
- [x] Each state in the coverage list above has an Operations test showing
      whether a day is counted and whether the panel is shown.
- [x] No trial day is counted at launch: `recordTrialUsageOnLaunch` no longer
      exists anywhere in `Sources/` or `Tests/` (gated in `check_command`).
- [x] A stored `expired` with no record loads as `trialExpired`, and a stored
      `expired` with a record loads as `expired` (Infra tests, gated by
      `grep -rq 'trialExpired' Tests/SuttoInfraTests/`).
- [x] `LicensePresentation.statusText` returns the spent-trial text for
      `trialExpired` and the license-expired text for `expired` (Operations
      test).
