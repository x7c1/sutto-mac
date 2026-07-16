import SuttoDomain
import Testing

@testable import SuttoOperations

/// A `TargetWindow` stub the fake controller hands back on capture.
private final class TargetWindowStub: TargetWindow {}

/// A `WindowControlling` stub whose capture yields a stub target (or none),
/// with a scriptable identity so tests can assert what `capture()`
/// snapshots. Records how many times `identity(of:)` was asked, to prove the
/// snapshot is taken exactly once at capture.
@MainActor
private final class WindowControllerStub: WindowControlling {
    var captureSucceeds: Bool
    var scriptedIdentity: WindowIdentity
    private let target = TargetWindowStub()
    private(set) var identityReadCount = 0

    init(captureSucceeds: Bool = true, identity: WindowIdentity) {
        self.captureSucceeds = captureSucceeds
        scriptedIdentity = identity
    }

    func captureFocusedWindow() -> TargetWindow? {
        captureSucceeds ? target : nil
    }

    func identity(of window: TargetWindow) -> WindowIdentity {
        identityReadCount += 1
        return scriptedIdentity
    }

    func frame(of window: TargetWindow) -> PixelRect? { nil }
    func applyFrame(_ frame: PixelRect, to window: TargetWindow) -> Bool { true }
}

@Suite @MainActor struct PanelTargetSessionTests {
    /// Before any capture there is nothing to identify.
    @Test func hasNoIdentityBeforeCapture() {
        let session = PanelTargetSession(
            windows: WindowControllerStub(
                identity: WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home")))
        #expect(session.targetIdentity() == nil)
    }

    /// Capture snapshots the frontmost app's bundle identifier and the
    /// window's title, and hands them back through `targetIdentity()`.
    @Test func capturesBundleIdentifierAndTitle() {
        let windows = WindowControllerStub(
            identity: WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home"))
        let session = PanelTargetSession(windows: windows)

        session.capture()

        #expect(
            session.targetIdentity()
                == WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home"))
    }

    /// A missing bundle identifier does not fail capture — the target is
    /// still captured and the identity is held with a `nil` bundle
    /// identifier (the history layer decides to skip recording, not here).
    @Test func capturesEvenWhenBundleIdentifierIsMissing() {
        let windows = WindowControllerStub(
            identity: WindowIdentity(bundleIdentifier: nil, title: "Untitled"))
        let session = PanelTargetSession(windows: windows)

        session.capture()

        #expect(session.targetFrame() == nil)  // frame read still routed
        #expect(
            session.targetIdentity()
                == WindowIdentity(bundleIdentifier: nil, title: "Untitled"))
    }

    /// An empty title is kept as an empty string, not collapsed to `nil`:
    /// a blank-title window is still a distinct, keyable identity.
    @Test func keepsAnEmptyTitleAsEmptyString() {
        let windows = WindowControllerStub(
            identity: WindowIdentity(bundleIdentifier: "com.example.App", title: ""))
        let session = PanelTargetSession(windows: windows)

        session.capture()

        #expect(session.targetIdentity()?.title == "")
        #expect(session.targetIdentity()?.bundleIdentifier == "com.example.App")
    }

    /// An unreadable title (the AX read failed) is held as `nil`, still
    /// alongside the bundle identifier.
    @Test func holdsANilTitleWhenUnreadable() {
        let windows = WindowControllerStub(
            identity: WindowIdentity(bundleIdentifier: "com.example.App", title: nil))
        let session = PanelTargetSession(windows: windows)

        session.capture()

        #expect(
            session.targetIdentity()
                == WindowIdentity(bundleIdentifier: "com.example.App", title: nil))
    }

    /// When nothing is captured (no focused window, or the Accessibility
    /// permission is missing) the identity is cleared, and no identity read
    /// is even attempted.
    @Test func clearsIdentityWhenNothingIsCaptured() {
        let windows = WindowControllerStub(
            captureSucceeds: false,
            identity: WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home"))
        let session = PanelTargetSession(windows: windows)

        session.capture()

        #expect(session.targetIdentity() == nil)
        #expect(windows.identityReadCount == 0)
    }

    /// The identity is snapshotted exactly once, at capture: a later change
    /// to the window's title does not alter what the session reports, and
    /// the identity is not re-read on every `targetIdentity()` call — this is
    /// the one-target-per-opening invariant applied to identity.
    @Test func snapshotsIdentityOnceAtCaptureTime() {
        let windows = WindowControllerStub(
            identity: WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home"))
        let session = PanelTargetSession(windows: windows)

        session.capture()
        // The live window's title changes after capture.
        windows.scriptedIdentity = WindowIdentity(
            bundleIdentifier: "com.apple.Safari", title: "Downloads")

        #expect(
            session.targetIdentity()
                == WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home"))
        _ = session.targetIdentity()
        #expect(windows.identityReadCount == 1)
    }

    /// Re-capturing replaces the previously snapshotted identity, matching
    /// the way a fresh opening replaces the previous target.
    @Test func recaptureReplacesTheSnapshottedIdentity() {
        let windows = WindowControllerStub(
            identity: WindowIdentity(bundleIdentifier: "com.apple.Safari", title: "Home"))
        let session = PanelTargetSession(windows: windows)

        session.capture()
        windows.scriptedIdentity = WindowIdentity(
            bundleIdentifier: "com.apple.Terminal", title: "zsh")
        session.capture()

        #expect(
            session.targetIdentity()
                == WindowIdentity(bundleIdentifier: "com.apple.Terminal", title: "zsh"))
    }
}
