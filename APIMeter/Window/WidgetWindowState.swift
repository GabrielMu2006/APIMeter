import Foundation

/// Persisted state for the desktop widget panel: position and click-through
/// mode. Same contract as WindowState - UserDefaults only, NEVER any
/// secrets here (Keychain only).
public struct WidgetWindowState: Equatable, Sendable {
    public var frame: CGRect?
    /// True = pure display mode (mouse events pass through to windows below).
    public var clickThrough: Bool

    public init(frame: CGRect? = nil, clickThrough: Bool = false) {
        self.frame = frame
        self.clickThrough = clickThrough
    }

    private enum Keys {
        static let frame = "widget.state.frame"
        static let clickThrough = "widget.state.clickThrough"
    }

    public static func load(from defaults: UserDefaults) -> WidgetWindowState {
        var state = WidgetWindowState()
        if let raw = defaults.string(forKey: Keys.frame) {
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                state.frame = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
        if defaults.object(forKey: Keys.clickThrough) != nil {
            state.clickThrough = defaults.bool(forKey: Keys.clickThrough)
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
        defaults.set(clickThrough, forKey: Keys.clickThrough)
    }
}
