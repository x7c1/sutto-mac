# Sutto for macOS

> **UNDER DEVELOPMENT** - This app is currently in active development and not yet functional.

A window snapping app for macOS, bringing the [Sutto](https://github.com/x7c1/sutto) experience to the Mac as a menu bar app.

## Development

### Requirements

- macOS 14 or later
- Swift 6.0 or later (the Xcode Command Line Tools are sufficient; a full Xcode installation is not required)

### Build and run

```sh
swift build   # build the SwiftPM package
make test     # run unit tests (wraps `swift test`; see the Makefile)
make app      # assemble .build/Sutto.app
make run      # build the bundle and launch it
```

The app lives in the menu bar (no Dock icon). During development the bundle is unsigned, so macOS treats every rebuilt binary as a new app: you have to grant (or re-grant) the Accessibility permission manually under System Settings › Privacy & Security › Accessibility. The onboarding window shown at first launch walks through this.

## License

This project is licensed under the GNU General Public License v3.0 or later - see the [LICENSE](LICENSE) file for details.
