import Foundation
import WidgetKit

/// Compact snapshot handed to the WidgetKit extension. Written by the main
/// app after every successful refresh; the extension only ever reads this
/// file (no network, no keychain, no GRDB there - the widget process has a
/// strict memory budget).
///
/// The extension carries its own field-compatible Codable mirror of this
/// struct; keep the two in sync (field names are the contract).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var writtenAt: Date
    public var balance: BalanceInfo?
    public var providers: [ProviderInfo]

    public struct BalanceInfo: Codable, Equatable, Sendable {
        public var total: Decimal
        public var currency: String
        public var today: Decimal?
        public var isAvailable: Bool
        public var fetchedAt: Date?

        public init(total: Decimal, currency: String, today: Decimal?, isAvailable: Bool, fetchedAt: Date?) {
            self.total = total
            self.currency = currency
            self.today = today
            self.isAvailable = isAvailable
            self.fetchedAt = fetchedAt
        }
    }

    public struct ProviderInfo: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var displayName: String
        public var available: Bool
        /// True when the data came from the Codex CLI session log instead of
        /// the live endpoint (shown as an "offline" marker in the widget).
        public var offline: Bool
        public var planLevel: String?
        public var fetchedAt: Date?
        public var windows: [WindowInfo]

        public init(id: String, displayName: String, available: Bool, offline: Bool, planLevel: String?, fetchedAt: Date?, windows: [WindowInfo]) {
            self.id = id
            self.displayName = displayName
            self.available = available
            self.offline = offline
            self.planLevel = planLevel
            self.fetchedAt = fetchedAt
            self.windows = windows
        }
    }

    public struct WindowInfo: Codable, Equatable, Sendable {
        /// QuotaWindowKind raw value ("fiveHour" / "weekly" / "monthly" / ...).
        public var kind: String
        /// Remaining share 0-100 (nil when unknown).
        public var remainingPercent: Double?
        /// Compact remaining amount preformatted by the app ("2k", "1660").
        public var remainingLabel: String?
        public var resetsAt: Date?

        public init(kind: String, remainingPercent: Double?, remainingLabel: String? = nil, resetsAt: Date?) {
            self.kind = kind
            self.remainingPercent = remainingPercent
            self.remainingLabel = remainingLabel
            self.resetsAt = resetsAt
        }
    }

    public init(version: Int = 1, writtenAt: Date, balance: BalanceInfo?, providers: [ProviderInfo]) {
        self.version = version
        self.writtenAt = writtenAt
        self.balance = balance
        self.providers = providers
    }
}

/// Writes the widget snapshot and asks the system to reload the timelines.
/// View models signal changes via `postDataChange()`; bursts are coalesced
/// into one write about a second after the last signal.
@MainActor
public final class WidgetStateStore {
    public static let dataDidChange = Notification.Name("com.apimeter.widgetDataDidChange")
    private static let debounceInterval: Duration = .seconds(1)

    /// Bundle id of the widget extension. The extension is sandboxed and can
    /// only read inside its own container - which the unsandboxed main app
    /// CAN write (App Groups would be the canonical channel but restricted
    /// entitlements require a real signing certificate, which this project
    /// deliberately does not use).
    static let widgetBundleID = "com.apimeter.mac.quota-widget"

    private let fileURL: URL
    private var flushTask: Task<Void, Never>?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dataDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(Self.widgetBundleID, isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
            self.fileURL = dataDir.appendingPathComponent("widget-state.json")
        }
    }

    /// View models call this after any widget-relevant data change.
    public static func postDataChange() {
        NotificationCenter.default.post(name: dataDidChange, object: nil)
    }

    /// Subscribes to data-change signals and writes + reloads on each burst.
    /// The returned token must be retained for the observer's lifetime.
    public func observeAndPublish(collector: @escaping @MainActor () -> WidgetSnapshot) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: Self.dataDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleFlush(collector: collector)
            }
        }
    }

    private func scheduleFlush(collector: @escaping @MainActor () -> WidgetSnapshot) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            self?.flushNow(collector: collector)
        }
    }

    private func flushNow(collector: @escaping @MainActor () -> WidgetSnapshot) {
        write(collector())
    }

    public func write(_ snapshot: WidgetSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
            Log.info("Widget state written (" + String(snapshot.providers.filter(\.available).count) + " providers available)")
        } catch {
            Log.error("Widget state write failed: " + error.localizedDescription)
        }
    }
}
