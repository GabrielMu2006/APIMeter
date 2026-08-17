import AppKit
import SwiftUI

/// Owns the floating dashboard NSPanel (spec 46-48).
/// Pin ON -> NSWindow.Level.floating, Pin OFF -> normal (spec 47).
/// Frame, size, pin and mini state persist across launches.
@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var savedState: WindowState
    private let state: AppState
    private let defaults: UserDefaults
    private var currentMode: WindowMode = .full

    public enum WindowMode: Sendable {
        case full
        case mini
    }

    public init(state: AppState, defaults: UserDefaults = .standard) {
        self.state = state
        self.defaults = defaults
        self.savedState = WindowState.load(from: defaults)
    }

    public var isVisible: Bool { panel?.isVisible ?? false }
    public var isPinned: Bool { savedState.pinned }
    public var mode: WindowMode { currentMode }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show(mode: WindowMode? = nil) {
        let target = mode ?? (savedState.mini ? WindowMode.mini : .full)
        Log.info("FloatingPanelController.show(mode: \(target == .full ? "full" : "mini"))")
        if panel == nil {
            createPanel(mode: target)
        } else {
            setMode(target)
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

    public func setMini(_ mini: Bool) {
        setMode(mini ? .mini : .full)
        savedState.mini = mini
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

    private func createPanel(mode: WindowMode) {
        let panel = NSPanel(
            contentRect: savedState.frame ?? defaultFrame,
            styleMask: mode == .full ? [.titled, .closable, .resizable, .fullSizeContentView] : [.borderless, .nonactivatingPanel],
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
        panel.contentView = hostingView(for: mode)
        if mode == .mini {
            panel.setContentSize(NSSize(width: 260, height: 70))
        }
        self.panel = panel
        self.currentMode = mode
        Log.info("FloatingPanelController: panel created mode=\(mode == .full ? "full" : "mini") frame=\(panel.frame)")
    }

    private func setMode(_ mode: WindowMode) {
        guard let panel else { return }
        if mode == currentMode { return }
        currentMode = mode
        if mode == .full {
            panel.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            panel.titlebarAppearsTransparent = true
            if let frame = savedState.frame {
                panel.setFrame(frame, display: true)
            }
        } else {
            // Save the full frame before shrinking into mini.
            saveState()
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.titlebarAppearsTransparent = false
        }
        panel.contentView = hostingView(for: mode)
        if mode == .mini {
            panel.setContentSize(NSSize(width: 260, height: 70))
        } else if let frame = savedState.frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func hostingView(for mode: WindowMode) -> NSView {
        let root: AnyView
        switch mode {
        case .full:
            root = AnyView(DashboardView(state: state))
        case .mini:
            root = AnyView(
                MiniPanelView(state: state)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .onTapGesture(count: 2) { self.setMini(false) }
            )
        }
        let hosting = NSHostingView(rootView: root)
        if mode == .mini {
            hosting.sizingOptions = [.preferredContentSize]
        } else {
            hosting.autoresizingMask = [.width, .height]
        }
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
        if let frame = panel?.frame, currentMode == .full {
            savedState.frame = frame
        }
        savedState.mini = (currentMode == .mini)
        savedState.save(to: defaults)
    }

    // MARK: - NSWindowDelegate

    public func windowDidMove(_ notification: Notification) { saveState() }
    public func windowDidResize(_ notification: Notification) { saveState() }
    public func windowWillClose(_ notification: Notification) { saveState() }
}
