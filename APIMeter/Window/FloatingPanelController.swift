import AppKit
import SwiftUI

/// Owns the floating dashboard NSPanel (spec 46-48).
/// Pin ON -> NSWindow.Level.floating, Pin OFF -> normal (spec 47).
/// Frame and pin state persist across launches.
@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var savedState: WindowState
    private let state: AppState
    private let defaults: UserDefaults

    /// Full-mode minimum, kept in sync with DashboardView's min frame so a
    /// saved (smaller) frame from an older build can never clip the content.
    private static let fullMinSize = NSSize(width: 940, height: 680)

    public init(state: AppState, defaults: UserDefaults = .standard) {
        self.state = state
        self.defaults = defaults
        self.savedState = WindowState.load(from: defaults)
    }

    public var isVisible: Bool { panel?.isVisible ?? false }
    public var isPinned: Bool { savedState.pinned }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        Log.info("FloatingPanelController.show()")
        if panel == nil {
            createPanel()
        }
        orderFront()
        Log.info("FloatingPanelController: isVisible=\(panel?.isVisible ?? false) frame=\(String(describing: panel?.frame))")
    }

    public func hide() {
        saveState()
        panel?.orderOut(nil)
        state.notePanelHidden()
    }

    public func togglePin() {
        savedState.pinned.toggle()
        panel?.level = savedState.pinned ? .floating : .normal
        saveState()
    }

    public func refreshNow() {
        Task { await state.refreshAll() }
    }

    // MARK: - Panel lifecycle

    private var defaultFrame: CGRect {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 980, height: 680)
        let width: CGFloat = 980
        let height: CGFloat = 680
        return CGRect(
            x: screen.midX - width / 2,
            y: screen.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func createPanel() {
        let contentRect: CGRect
        if let saved = savedState.frame {
            // Keep where the user parked it, but never below the content min.
            contentRect = CGRect(
                x: saved.origin.x, y: saved.origin.y,
                width: max(saved.width, Self.fullMinSize.width),
                height: max(saved.height, Self.fullMinSize.height)
            )
        } else {
            contentRect = defaultFrame
        }
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "API Meter"
        panel.isFloatingPanel = true
        panel.level = savedState.pinned ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.delegate = self
        panel.contentView = hostingView()
        panel.contentMinSize = Self.fullMinSize
        self.panel = panel
        Log.info("FloatingPanelController: panel created frame=\(panel.frame)")
    }

    private func hostingView() -> NSView {
        let hosting = NSHostingView(rootView: DashboardView(state: state))
        hosting.autoresizingMask = [.width, .height]
        return hosting
    }

    private func orderFront() {
        guard let panel else { return }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        state.notePanelShown()
    }

    private func saveState() {
        if let frame = panel?.frame {
            savedState.frame = frame
        }
        savedState.save(to: defaults)
    }

    // MARK: - NSWindowDelegate

    public func windowDidMove(_ notification: Notification) { saveState() }
    public func windowDidResize(_ notification: Notification) { saveState() }
    public func windowWillClose(_ notification: Notification) { saveState() }
}
