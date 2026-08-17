import AppKit

/// Adaptive refresh (spec 55):
/// - floating panel visible: every 5 minutes
/// - menu bar only: every 15 minutes
/// - sleep: stop; wake: refresh immediately
/// Manual refresh is always available from the UI.
@MainActor
public final class RefreshCoordinator {
    private let state: AppState
    private var timer: Timer?

    public init(state: AppState) {
        self.state = state
    }

    public func start() {
        schedule(interval: 15 * 60)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.timer?.invalidate() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.state.refreshAll()
                self?.reschedule()
            }
        }
    }

    public func notePanelVisibilityChanged(visible: Bool) {
        schedule(interval: visible ? 5 * 60 : 15 * 60)
        if visible {
            Task { await state.refreshAll() }
        }
    }

    private func reschedule() {
        let visible = state.floatingPanelController?.isVisible ?? false
        schedule(interval: visible ? 5 * 60 : 15 * 60)
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.state.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
