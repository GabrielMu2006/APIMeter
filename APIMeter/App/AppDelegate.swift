import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no dock icon by default (LSUIElement=YES in Info.plist
        // also covers this; accessory keeps activation sane for settings).
        NSApp.setActivationPolicy(.accessory)
        // Verification aid: bring the dashboard to the front when requested.
        if ProcessInfo.processInfo.environment["APIMETER_OPEN_DASHBOARD"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
