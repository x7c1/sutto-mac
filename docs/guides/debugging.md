# Debugging and Logging

## Overview

Sutto logs through the unified logging system (`os.Logger`) under the subsystem `io.github.x7c1.SuttoMac`. This guide covers how to watch those logs during development and the macOS quirks that make them easy to miss: privacy redaction, log levels, and `open` reusing a running instance.

## Watching logs

Stream the app's own log lines (and nothing else):

```sh
log stream --info --predicate 'process == "Sutto" AND subsystem == "io.github.x7c1.SuttoMac"' --style compact
```

- `--info` is required: most of Sutto's development logs use the `info` level, which `log stream` hides by default.
- To inspect events after the fact instead of streaming, use `log show`:

  ```sh
  log show --info --last 5m --predicate 'process == "Sutto" AND subsystem == "io.github.x7c1.SuttoMac"' --style compact
  ```

A successful line looks like:

```
19:34:56.454 I  Sutto[95271:16a284] [io.github.x7c1.SuttoMac:selection] layout selected: Left Half
```

## Privacy redaction (`<private>`)

Unified logging redacts dynamic strings (format arguments) as `<private>` unless they are explicitly marked public. Development-facing values must opt out of redaction:

```swift
Logger(subsystem: "io.github.x7c1.SuttoMac", category: "selection")
    .info("layout selected: \(layout.label, privacy: .public)")
```

Follow this pattern for new log statements: `os.Logger` with the shared subsystem, a short category per feature, and `privacy: .public` on values a developer needs to read. Do not mark values public if they could contain end-user content (file paths, window titles).

`NSLog` is not used: its formatted message is redacted in `log stream`, and it lacks subsystem/category filtering.

## Keeping the Accessibility permission across rebuilds

TCC (the permission system behind System Settings › Privacy & Security)
identifies an app by its code signature. An unsigned build has no stable
identity — macOS treats every rebuilt binary as a brand-new app — so the
Accessibility grant you gave the previous build does not apply to the next
one, and window placement silently stops working until you re-grant it.

Signing the bundle with *any* stable identity fixes this: the signature (not
the file path) is what TCC keys the grant on, so every rebuild signed with
the same identity keeps the permission. A local self-signed certificate is
enough; this is purely a development convenience and has nothing to do with
distribution signing or notarization.

### Creating a local code-signing certificate (one-time)

1. Open **Keychain Access** (in `/Applications/Utilities`).
2. Menu bar: **Keychain Access › Certificate Assistant › Create a
   Certificate…**
3. Fill in the assistant:
   - **Name**: something recognizable, e.g. `Sutto Dev` (this string is the
     identity you pass to `make`).
   - **Identity Type**: `Self-Signed Root`.
   - **Certificate Type**: `Code Signing`.
4. Click **Create**, then **Done**. The certificate lands in your login
   keychain.
5. **Mark it trusted** — on current macOS the assistant does NOT auto-trust
   self-signed certificates, so the identity stays invalid
   (`CSSMERR_TP_NOT_TRUSTED`) until you do this: double-click the
   certificate in Keychain Access, expand **Trust**, set **When using this
   certificate** to **Always Trust**, and close the window (you will be
   asked for your password).
6. Verify that `codesign` sees exactly one VALID identity:

   ```sh
   security find-identity -p codesigning -v
   ```

   The output must say `1 valid identities found` with `"Sutto Dev"`.
   Gotchas seen in practice:
   - `0 valid identities found` but the plain (non-`-v`) listing shows the
     certificate with `CSSMERR_TP_NOT_TRUSTED` → step 5 was skipped.
   - Two `"Sutto Dev"` entries (the assistant was run twice) → `codesign`
     will refuse the name as ambiguous; delete one of the duplicates in
     Keychain Access.
   - Every build shows a password dialog — “codesign wants to sign using
     key "Sutto Dev" in your keychain” → click **Always Allow** once
     (clicking plain Allow re-prompts on every build). If the dialog keeps
     coming back, open the private key in Keychain Access (login keychain →
     Keys category → the `Sutto Dev` key) → **Access Control** → select
     “Allow all applications to access this item”. The key is a
     development-only self-signed key, so this is safe.

### Usage

Recommended: create a git-ignored `local.mk` next to the `Makefile` (it is
`-include`d automatically), so every build in this checkout signs — no
matter which shell, tool, or agent runs `make`:

```make
# local.mk — per-machine settings, not committed
CODESIGN_IDENTITY := Sutto Dev
```

Alternatively pass the variable per invocation
(`make run CODESIGN_IDENTITY="Sutto Dev"`) or export it in your shell
profile — but note both of those silently stop applying in shells without
the export (a fresh terminal, another tool's shell), and every unsigned
build you launch re-triggers the permission dance. `local.mk` avoids that
failure mode.

The first signed build still needs one manual grant under System Settings ›
Privacy & Security › Accessibility (it is a new identity), but every rebuild
after that keeps the permission. Verify what a bundle was actually signed
with via `codesign -dv .build/Sutto.app` (unsigned builds show
`Signature=adhoc`).

## Gotchas

- **`open` alone does not restart a running instance** — it only activates an already-running Sutto instead of launching a rebuilt binary. `make run` handles this for you by quitting any running instance before `open`. If you launch by other means, quit first (status menu → Quit Sutto, or `pkill -x Sutto`). The PID in the log lines tells you whether a new process actually started.
- **stderr alternative:** running the bundled binary directly attaches it to your terminal, so anything written to stderr is visible without `log stream`:

  ```sh
  .build/Sutto.app/Contents/MacOS/Sutto
  ```

  Quit with Ctrl-C.
