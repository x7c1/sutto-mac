# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

Sutto for macOS: a menu bar window-snapping app. Swift, AppKit, SwiftPM (no Xcode project). License: GPLv3 or later.

## Build and test

```sh
swift build   # build the package
make test     # run unit tests (preferred over bare `swift test`, see below)
make app      # assemble .build/Sutto.app from the release binary + Packaging/Info.plist
make run      # make app + open the bundle
make clean    # remove the bundle and SwiftPM build artifacts
```

- Use `make test` instead of bare `swift test`: on machines with only the Xcode Command Line Tools, SwiftPM does not locate Swift Testing on its own, and the Makefile injects the required compiler/linker paths. With a full Xcode toolchain the flags are empty and `make test` degrades to plain `swift test`.
- `make app` is required to exercise `LSUIElement` behavior; the bare SwiftPM binary runs without a bundle and falls back to the `.accessory` activation policy set in code.

## Architecture

Five SwiftPM targets, layered with dependencies pointing inward toward the domain (see [docs/guides/architecture.md](docs/guides/architecture.md) for the full picture):

- `SuttoDomain` — pure domain models and logic; no macOS framework imports.
- `SuttoOperations` — use cases plus the protocols that infra implements.
- `SuttoInfra` — concrete adapters over Apple frameworks (Accessibility APIs etc.).
- `SuttoUI` — everything on screen (status item, windows, menus).
- `SuttoApp` — executable composition root: wiring and app lifecycle only.

The dependency rules are declared in `Package.swift`, so a forbidden import fails to compile. All non-trivial logic belongs in `SuttoDomain`/`SuttoOperations`, where it is unit-tested with Swift Testing (`Tests/SuttoDomainTests`, `Tests/SuttoOperationsTests`).

## Testing strategy

- Unit tests cover SuttoDomain and SuttoOperations and run everywhere, including CI.
- End-to-end tests that actually move or resize windows require the Accessibility (TCC) permission, which cannot be granted in CI. They are local-only; CI runs unit tests exclusively.

## Conventions

- Commit messages: Conventional Commits, written in English (e.g. `feat: add snap layout parser`).
- Code comments, documentation, and PR descriptions in English.
- No third-party dependencies without prior discussion.
- Follow the Swift API Design Guidelines.
