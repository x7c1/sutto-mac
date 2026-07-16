import AppKit

/// The "Buy License…" destination, shared by the License settings pane and the
/// status-menu row so both open the same checkout.
///
/// TODO(sub-PR B5): replace ``checkoutURL`` with the real Lemon Squeezy
/// checkout URL (product / variant confirmed) once the store is set up. It is a
/// non-resolving placeholder for now, so the button is fully wired but the page
/// it opens is not the real one yet — the UI skeleton lands ahead of the store
/// configuration.
@MainActor
enum LicensePurchaseLink {
    /// Placeholder checkout URL. See the file's `TODO(sub-PR B5)`.
    static let checkoutURL = URL(string: "https://sutto.app/buy")!

    /// Opens the checkout in the user's default browser. The settings window
    /// and the status menu both call this, so the purchase path is defined once.
    static func open() {
        NSWorkspace.shared.open(checkoutURL)
    }
}
