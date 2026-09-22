import AppKit
import SwiftUI

/// Owns the desktop widget panel: a borderless, clear NSPanel that floats at
/// DESKTOP level (above the wallpaper, below ordinary windows), joins all
/// Spaces and stays put. The existing floating dashboard panel is untouched;
/// this is a separate window with its own persisted state.
///
/// - Drag anywhere to move (isMovableByWindowBackground).
/// - Click-through mode (ignoresMouseEvents) turns it into a pure display.
/// - Content size is driven by the SwiftUI view (hostingView sizing options).
@MainActor
public final class WidgetPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var savedState: WidgetWindowState
    private let state: AppState
    private let defaults: UserDefaults

    public init(state: AppState, defaults: UserDefaults = .standard) {
        self.state = state
        self.defaults = defaults
        self.savedState = WidgetWindowState.load(from: defaults)
    }

    public var isVisible: Bool { panel?.isVisible ?? false }
    public var isClickThrough: Bool { savedState.clickThrough }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFrontRegardless()
        // Desktop-level panels must not steal focus from the active app.
        Log.info("WidgetPanelController: shown frame=\(String(describing: panel?.frame))")
    }

    public func hide() {
        saveState()
        panel?.orderOut(nil)
    }

    /// Pure-display mode: the mouse passes through to windows below.
    public func setClickThrough(_ enabled: Bool) {
        savedState.clickThrough = enabled
        panel?.ignoresMouseEvents = enabled
        saveState()
    }

    public func toggleClickThrough() {
        setClickThrough(!savedState.clickThrough)
    }

    public func refreshNow() {
        Task { await state.refreshAll() }
    }

    // MARK: - Panel lifecycle

    private var defaultFrame: CGRect {
        // Park in the top-right corner of the main screen with a margin.
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = contentSize
        return CGRect(
            x: screen.maxX - size.width - 24,
            y: screen.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }

    /// The natural size of the widget grid; the panel always adopts the
    /// CURRENT content size (only the position is restored), so layout
    /// changes can never leave a stale frame clipping the cards. Height
    /// grows per provider row (Kimi, Qoder auto-detected).
    private var contentSize: NSSize {
        let cardWidth: CGFloat = 156
        let cardHeight: CGFloat = 116
        let wideCardHeight: CGFloat = 96
        let spacing: CGFloat = 12
        var rows: CGFloat = 1
        if state.kimiQuotaViewModel.hasCredential || state.kimiQuotaViewModel.quota != nil { rows += 1 }
        if state.qoderQuotaViewModel.hasCredential || state.qoderQuotaViewModel.quota != nil { rows += 1 }
        if state.codexQuotaViewModel.hasCredential || state.codexQuotaViewModel.quota != nil { rows += 1 }
        return NSSize(
            width: cardWidth * 2 + spacing,
            height: (cardHeight + spacing) * rows + wideCardHeight
        )
    }

    private func createPanel() {
        let size = contentSize
        let frame: CGRect
        if let saved = savedState.frame {
            // Keep where the user parked it, but always the current size.
            frame = CGRect(x: saved.origin.x, y: saved.origin.y, width: size.width, height: size.height)
        } else {
            frame = defaultFrame
        }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Desktop level: above the wallpaper, below ordinary windows - like
        // the system's own desktop widgets. Stationary + all Spaces keeps it
        // pinned where the user dropped it; fullscreen apps cover it.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.ignoresMouseEvents = savedState.clickThrough
        panel.delegate = self
        let hosting = NSHostingView(rootView: DesktopWidgetsView(state: state))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        self.panel = panel
    }

    private func saveState() {
        if let frame = panel?.frame {
            savedState.frame = frame
        }
        savedState.save(to: defaults)
    }

    // MARK: - NSWindowDelegate

    public func windowDidMove(_ notification: Notification) { saveState() }
}
