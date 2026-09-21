import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut: show/hide the dashboard (spec 49).
    /// Default: Option+Space (user-changeable in Settings > General).
    nonisolated(unsafe) static let toggleDashboard = Self("toggleDashboard", default: .init(.space, modifiers: [.option]))
}

extension KeyboardShortcuts.Name {
    /// Global shortcut: show/hide the desktop widget panel.
    /// Default: Option+W (user-changeable in Settings > General).
    nonisolated(unsafe) static let toggleWidgets = Self("toggleWidgets", default: .init(.w, modifiers: [.option]))
}
