import AppKit

/// Adaptive refresh (spec 55):
/// - floating panel visible: local reload every 60 s, network every 5 min
/// - menu bar only: network every 15 min
/// - sleep: stop; wake: refresh immediately
@MainActor
public final class RefreshCoordinator {
    private let state: AppState
    private var networkTimer: Timer?

    public init(state: AppState) {
        self.state = state
    }

    public func start() {
        scheduleNetwork(interval: 15 * 60)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.networkTimer?.invalidate()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.state.refreshAll()
                self?.reschedule()
            }
        }
    }

    public func notePanelVisibilityChanged(visible: Bool) {
        if visible {
            // Visible: balance API is lightweight - refresh every minute so
            // Today (balance-derived) tracks spending closely.
            scheduleNetwork(interval: 60)
            Task { await state.refreshAll() }
        } else {
            scheduleNetwork(interval: 15 * 60)
        }
    }

    private func reschedule() {
        let visible = state.floatingPanelController?.isVisible ?? false
        notePanelVisibilityChanged(visible: visible)
    }

    private func scheduleNetwork(interval: TimeInterval) {
        networkTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.state.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        networkTimer = timer
    }
}
