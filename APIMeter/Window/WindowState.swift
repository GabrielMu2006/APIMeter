import Foundation

/// Persisted window state (spec 48): position, size, pin state, mini/full.
/// Stored in UserDefaults - NEVER any secrets here (Keychain only).
public struct WindowState: Equatable, Sendable {
    public var frame: CGRect?
    public var pinned: Bool
    public var mini: Bool

    public init(frame: CGRect? = nil, pinned: Bool = false, mini: Bool = false) {
        self.frame = frame
        self.pinned = pinned
        self.mini = mini
    }

    private enum Keys {
        static let frame = "window.state.frame"
        static let pinned = "window.state.pinned"
        static let mini = "window.state.mini"
    }

    public static func load(from defaults: UserDefaults) -> WindowState {
        var state = WindowState()
        if let raw = defaults.string(forKey: Keys.frame) {
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                state.frame = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
        if defaults.object(forKey: Keys.pinned) != nil {
            state.pinned = defaults.bool(forKey: Keys.pinned)
        }
        if defaults.object(forKey: Keys.mini) != nil {
            state.mini = defaults.bool(forKey: Keys.mini)
        }
        return state
    }

    public func save(to defaults: UserDefaults) {
        if let frame {
            let raw = [Double(frame.origin.x), Double(frame.origin.y), Double(frame.width), Double(frame.height)]
                .map { String($0) }
                .joined(separator: ",")
            defaults.set(raw, forKey: Keys.frame)
        }
        defaults.set(pinned, forKey: Keys.pinned)
        defaults.set(mini, forKey: Keys.mini)
    }
}
