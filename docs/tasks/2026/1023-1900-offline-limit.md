---
status: completed
pipeline_phase: null
plan: null
base_ref: null
perspectives: [completeness, clarity, user-experience]
max_refine_rounds: 3
retries_remaining: 1
check_command: "make build && make test && make app && grep -rq 'NWPathMonitor' Sources/SuttoInfra/ && ! grep -rqE 'import Network$' Sources/SuttoDomain/ Sources/SuttoOperations/ Sources/SuttoUI/ && grep -rq 'lastOnline' Tests/SuttoDomainTests/ && grep -rq 'lastOnline' Tests/SuttoOperationsTests/ && grep -rq 'lastOnline' Tests/SuttoInfraTests/"
assignee: null
branch: task/1023-1900-offline-limit
created_at: 2026-10-23T10:00:22Z
updated_at: 2026-10-23T10:20:03Z
---

# feat(licensing): limit offline use to 7 days from the last time the device was online

## Overview

The license gate contract shared with the GNOME version (x7c1/sutto) lets a
device use Sutto offline for at most 7 days. The 7 days are counted from the
last time the device was **online**. They are not counted from the last
successful validate. A device whose license server has gone away keeps
working as long as it keeps coming online. The macOS version has no
connectivity axis yet: a `valid` device stays open forever, even while
offline. The GNOME version implements this (`OFFLINE_GRACE_PERIOD_DAYS`,
`recordOnlineIfConnected`, `watchNetworkState`, and `isOfflineGraceExceeded`
in `src/operations/licensing/license-operations.ts`, plus
`src/domain/licensing/license-state.ts` in x7c1/sutto); follow it.

Keep two axes apart:

- **Connectivity**: whether the device is on a network. The OS tells us this.
- **Reachability**: whether the license server answered. Only a validate
  attempt tells us this.

Reachability handling stays as it is (no answer never downgrades).
Connectivity is new.

1. **Connectivity source.** Add a connectivity protocol in `SuttoOperations`.
   It reports whether the device is online now and calls back when that
   changes. Implement it in `SuttoInfra` with `NWPathMonitor` (`path.status
   == .satisfied` means online). Only `SuttoInfra` imports `Network`. Tests
   use a stub.
2. **Last-online time.** `LicenseState` gains a persisted `lastOnlineAt:
   Date`. `FileLicenseRepository` stores it. A file without it, a fresh
   trial, and a corrupt file all start it at the load time. Missing data
   never closes the gate.
3. **When it is recorded.** Record now as the last-online time whenever the
   device is online at:
   - launch, before the launch validate;
   - every panel-show attempt, before the gate is checked, so a device that
     has just reconnected opens at once;
   - every connectivity change, both to online and from online to offline.
     The device was online until it dropped.
4. **Validate only when online.** The launch validate is attempted only when
   the device is online. Offline is not treated as "no answer": it is handled
   by the 7-day rule.
5. **Gate decision.** `LicenseGatePolicy` gains the inputs it needs. Pass
   them as plain values, such as whether the device is online and the days
   since `lastOnlineAt` as of an injected `now`, so the Domain stays
   Foundation-only and clock-free. The rules:
   - A `valid` device is closed when it is offline **and** at least 7 days
     have passed since `lastOnlineAt`. Otherwise it is open.
   - A `trial` device is open whether online or offline; the trial is fully
     local.
   - `trialExpired`, `expired`, and `invalid` stay closed. A later task lets a
     spent trial reopen when the server does not answer; it will apply this
     same 7-day rule.
   Name the 7 days once as a constant, as the GNOME version does.
6. **What the user sees.** When the gate is closed for this reason, the
   status text (`LicensePresentation.statusText`, used by the status menu and
   the License settings pane) says the device has been offline too long and
   should reconnect to the internet. Use the GNOME wording as a guide: "This
   device has been offline for too long. Reconnect to the internet to
   continue." When the device reconnects, the gate opens on the next panel
   show without relaunching. If Settings is open, it is refreshed as it is
   for other licensing changes.

Operation × state coverage for "show the panel" (Domain or Operations tests):

- `valid`, online → open (and `lastOnlineAt` is updated)
- `valid`, offline, last online 6 days ago → open
- `valid`, offline, last online 7 or more days ago → closed, with the offline
  status text
- `valid`, offline for 8 days, then connectivity reports online → open on the
  next show, without relaunching
- `trial`, offline for 30 days → open
- `trialExpired` / `expired` / `invalid` → closed, online or offline
- stored file without `lastOnlineAt` → loads with the load time, gate decided
  as if just online

Launch validate coverage: online → validate attempted; offline → not
attempted, status unchanged.

Out of scope: the reachability probe for a spent trial (a separate task), and
any periodic re-validation.

## Acceptance criteria

### Automated (pipeline-verified)

- [x] Connectivity comes from `NWPathMonitor` in `SuttoInfra`, and `Network`
      is imported nowhere in `SuttoDomain`, `SuttoOperations`, or `SuttoUI`
      (both greps are in `check_command`).
- [x] `LicenseGatePolicy` closes a `valid` device only when it is offline and
      at least 7 days have passed since the last-online time, and keeps a
      `trial` device open while offline (Domain tests mentioning
      `lastOnline`, gated by `grep -rq 'lastOnline' Tests/SuttoDomainTests/`).
- [x] Every state in the panel-show coverage list above has a test, including
      reconnecting after 8 days offline, which opens the gate without a
      relaunch (Operations tests, gated by
      `grep -rq 'lastOnline' Tests/SuttoOperationsTests/`).
- [x] The launch validate is attempted only while online, and the last-online
      time is recorded at launch, on each panel-show attempt, and on each
      connectivity change into or out of online (Operations tests).
- [x] `FileLicenseRepository` round-trips `lastOnlineAt`, and a stored file
      without it loads with the load time (Infra tests, gated by
      `grep -rq 'lastOnline' Tests/SuttoInfraTests/`).
- [x] `LicensePresentation.statusText` shows the offline-too-long text for a
      `valid` device past the limit and the usual license text otherwise
      (Operations test).
