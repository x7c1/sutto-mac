# CLAUDE.md

Sutto for macOS: a menu bar window-snapping app. Swift, AppKit, SwiftPM (no Xcode project).

@README.md

## Build and test

- Use `make test`, never bare `swift test` — see [docs/guides/testing.md](docs/guides/testing.md) for why.
- Use `make app` / `make run` to exercise `LSUIElement` behavior; the bare SwiftPM binary has no bundle.

## Architecture

Five layered SwiftPM targets with dependency rules enforced by `Package.swift`; put all non-trivial logic in `SuttoDomain`/`SuttoOperations`, where it is unit-tested. See [docs/guides/architecture.md](docs/guides/architecture.md).

## Conventions

- Commit messages: Conventional Commits, written in English (e.g. `feat: add snap layout parser`).
- Code comments, documentation, and PR descriptions in English.
- No third-party dependencies without prior discussion.
- Follow the Swift API Design Guidelines.
