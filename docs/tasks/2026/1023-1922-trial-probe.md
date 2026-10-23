---
status: completed
pipeline_phase: null
plan: null
base_ref: null
perspectives: [completeness, clarity, user-experience]
max_refine_rounds: 3
retries_remaining: 1
check_command: "make build && make test && make app && grep -rq 'TrialProbeResult' Sources/SuttoDomain/ && grep -rq 'TrialProbeResult\\|trialProbe' Tests/SuttoDomainTests/ && grep -rq 'trialProbe' Tests/SuttoOperationsTests/ && grep -rq 'trialProbe' Tests/SuttoInfraTests/"
assignee: null
branch: task/1023-1922-trial-probe
created_at: 2026-10-23T10:22:35Z
updated_at: 2026-10-23T10:38:03Z
---

# feat(licensing): reopen a spent trial when the license server no longer answers

## Overview

The license gate is a reminder for people willing to pay, not an enforcement
mechanism. The client is open source, and a device could always write
`valid` into its local state. The contract shared with the GNOME version
(x7c1/sutto) uses that to make sure retiring the license server strands no
one. Every online launch on a device whose trial is spent asks the server
whether it is still there:

- server answers → the device stays closed;
- server does not answer → the gate opens.

The macOS version keeps a spent trial (`trialExpired`) closed whatever the
server does. The GNOME version implements this (`TrialProbeResult` in
`src/domain/licensing/trial-probe-result.ts`, `probeLicenseServer` and the
`trial-expired` branch of `getDisabledReason` in
`src/operations/licensing/license-operations.ts` in x7c1/sutto); follow it.

1. **Probe result.** Add a Domain value `TrialProbeResult` with three cases:
   `none` (not asked yet), `answered`, and `noResponse`. Store the raw values
   `"none"`, `"answered"`, `"no-response"`. `LicenseState` gains a persisted
   `trialProbeResult`. `FileLicenseRepository` stores it, and a file
   without it, or with an unknown value, loads as `none`.
2. **The probe.** At launch, when the status is `trialExpired` **and** the
   device is online, call the existing validate with an **empty license key
   and an empty activation id**. Store the outcome with the same
   classification as any validate:
   - `.valid` or `.rejected(_)` → `answered`. The server answered, whether it
     accepted or refused.
   - `.noResponse` → `noResponse`. This covers timeout, 5xx, DNS failure,
     404 / 410, and a 4xx without a known reason code.
   Offline, the probe is not attempted and the stored result is kept. The
   probe never changes the status; a spent trial stays `trialExpired`. Make
   sure the infra client sends the empty strings as-is. Do not let it
   short-circuit them; add an Infra test that the request body carries the
   empty `license_key` and `activation_id`. Like the launch validate, the
   probe must not overwrite a newer state recorded while the request was in
   flight (re-read the state after the await).
3. **Gate decision.** `LicenseGatePolicy` takes the probe result as a plain
   value. `trialExpired` is open only when the stored result is
   `noResponse`. The 7-day offline rule then applies exactly as it does for
   `valid`. Results `none` and `answered` keep it closed. Statuses `valid`,
   `trial`, `expired`, and `invalid` are unaffected; `expired` and `invalid`
   stay closed even when the server does not answer.
4. **What the user sees.** A spent trial that is open because the server did
   not answer must not keep showing the "Trial expired — activate a license
   to keep using Sutto" line as if it were locked. Give `statusText` a
   wording for that state that does not claim Sutto is locked. It may still
   invite the user to buy. After the launch probe changes the result,
   refresh Settings if it is open, as the other licensing changes do.

Operation × state coverage for the launch pass (Operations tests):

- `trialExpired`, online, server answers (`.rejected(.invalidKey)`) → result
  `answered`, gate closed
- `trialExpired`, online, `.noResponse` → result `noResponse`, gate open
- `trialExpired`, offline → not probed, stored result kept
- `trialExpired`, result `noResponse`, offline 7 or more days since last
  online → closed; under 7 days → open
- `trialExpired`, previously `noResponse`, online again and server now answers
  → `answered`, closed again
- `trial`, `valid`, `expired`, `invalid` → never probed
- probe in flight while the license is activated → the stored `valid` state
  is not overwritten

Gate coverage (Domain tests): `trialExpired` × {`none`, `answered`,
`noResponse`} × {online, offline < 7 days, offline ≥ 7 days}; `expired` /
`invalid` with `noResponse` stay closed.

Out of scope: a dedicated probe endpoint (the contract reuses validate), and
probing more than once per launch.

## Acceptance criteria

### Automated (pipeline-verified)

- [x] `TrialProbeResult` exists in `SuttoDomain` with `none` / `answered` /
      `noResponse`, and `LicenseGatePolicy` opens `trialExpired` only for
      `noResponse` within the 7-day offline limit (Domain tests, gated by the
      `TrialProbeResult` greps in `check_command`).
- [x] Every launch-pass case in the coverage list above has an Operations
      test (gated by `grep -rq 'trialProbe' Tests/SuttoOperationsTests/`).
- [x] The probe is a validate with an empty license key and an empty
      activation id, sent as-is in the request body (Infra test).
- [x] `FileLicenseRepository` round-trips `trialProbeResult`, and a file
      without it or with an unknown value loads as `none` (Infra tests, gated
      by `grep -rq 'trialProbe' Tests/SuttoInfraTests/`).
- [x] `statusText` shows a non-locked wording for an open spent trial and the
      existing "Trial expired" wording for a closed one (Operations test).
