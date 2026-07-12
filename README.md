# Sutto for macOS

[![CI](https://github.com/x7c1/sutto-mac/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/x7c1/sutto-mac/actions/workflows/ci.yml)

> **UNDER DEVELOPMENT** - This app is currently in active development and not yet functional.

A window snapping app for macOS, bringing the [Sutto](https://github.com/x7c1/sutto) experience to the Mac as a menu bar app.

## Development

### Requirements

- macOS 14 or later
- Swift 6.0 or later (the Xcode Command Line Tools are sufficient; a full Xcode installation is not required)

### Build and run

| Command       | Description                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| `swift build` | Build the SwiftPM package                                                            |
| `make test`   | Run unit tests ([why not bare `swift test`](docs/guides/testing.md))                 |
| `make app`    | Assemble `.build/Sutto.app`                                                          |
| `make run`    | Build the bundle and (re)launch it, quitting any running instance                    |
| `make clean`  | Remove the bundle and SwiftPM build artifacts                                        |

The app lives in the menu bar (no Dock icon). During development the bundle is unsigned, so macOS treats every rebuilt binary as a new app: you have to grant (or re-grant) the Accessibility permission manually under System Settings › Privacy & Security › Accessibility. The onboarding window shown at first launch walks through this. To keep the permission across rebuilds, sign the bundle with a local self-signed certificate via `make run CODESIGN_IDENTITY="..."` — see [Keeping the Accessibility permission across rebuilds](docs/guides/debugging.md#keeping-the-accessibility-permission-across-rebuilds).

To watch the app's logs while verifying behavior, see [Debugging and Logging](docs/guides/debugging.md).

## License

This project is licensed under the GNU General Public License v3.0 or later - see the [LICENSE](LICENSE) file for details.
