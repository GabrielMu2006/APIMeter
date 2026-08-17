import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut: show/hide the dashboard (spec 49).
    /// Default: Option+Space (user-changeable in Settings > General).
    nonisolated(unsafe) static let toggleDashboard = Self("toggleDashboard", default: .init(.space, modifiers: [.option]))
}
