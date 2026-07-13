import AppKit

/// The settings window's tabs, in toolbar order. Each case knows its
/// user-facing title (also the window title while selected, the standard
/// macOS preferences behavior) and its SF Symbol toolbar icon.
///
/// Adding a tab is: add a case here (title + symbol), and teach
/// `SettingsWindowController.makePane(for:)` to build its pane — the
/// toolbar item, selection persistence, and window sizing follow from the
/// case list. A future License tab, for example, slots in as
/// `case license` plus one pane class.
enum SettingsTab: String, CaseIterable {
    /// Collection list, space preview, and import — the analogue of the
    /// GNOME preferences' Spaces page.
    case layouts

    /// The panel-toggle shortcut capture field and its reset.
    case shortcuts

    /// The toolbar label, and the window title while the tab is selected.
    var title: String {
        switch self {
        case .layouts: return "Layouts"
        case .shortcuts: return "Shortcuts"
        }
    }

    /// The toolbar icon. SF Symbols only — no bundled assets.
    var symbolName: String {
        switch self {
        case .layouts: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        }
    }

    /// `UserDefaults` key remembering the last-selected tab across window
    /// opens (and app relaunches). Pure window state — which is why it
    /// lives here as a raw defaults key instead of going through
    /// `PreferencesRepository`, whose entries mirror the GNOME GSettings
    /// schema.
    static let selectedTabDefaultsKey = "settingsSelectedTab"

    /// The tab to select when the window opens: the remembered one, or
    /// ``layouts`` on first use (the primary surface — it is where the
    /// GNOME preferences open too).
    static func restored(from defaults: UserDefaults = .standard) -> SettingsTab {
        defaults.string(forKey: selectedTabDefaultsKey)
            .flatMap(SettingsTab.init(rawValue:)) ?? .layouts
    }

    /// Remembers this tab as the one to restore next time.
    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.selectedTabDefaultsKey)
    }
}
