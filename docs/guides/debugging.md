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

## Gotchas

- **`make run` does not restart a running instance.** It ends in `open`, which only activates an already-running Sutto instead of launching the rebuilt binary. Quit first (status menu → Quit Sutto, or `pkill -x Sutto`), then `make run`. The PID in the log lines tells you whether a new process actually started.
- **stderr alternative:** running the bundled binary directly attaches it to your terminal, so anything written to stderr is visible without `log stream`:

  ```sh
  .build/Sutto.app/Contents/MacOS/Sutto
  ```

  Quit with Ctrl-C.
