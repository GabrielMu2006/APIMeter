import Foundation
import Testing
import APIMeterCore

struct SyncSetupTests {

    @Test func archiveURLUsesAppVersionTag() {
        let url = DeepSeekSyncInstaller.archiveURL(tag: "1.2.2")
        #expect(url.absoluteString == "https://github.com/GabrielMu2006/APIMeter/archive/refs/tags/v1.2.2.zip")
    }

    @Test func locateModuleFindsDeepSeekSyncDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds-test-" + UUID().uuidString, isDirectory: true)
        let module = base.appendingPathComponent("APIMeter-1.2.2/DeepSeekSync", isDirectory: true)
        try FileManager.default.createDirectory(at: module.appendingPathComponent("scripts", isDirectory: true), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: module.appendingPathComponent("package.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: module.appendingPathComponent("deepseek-sync").path, contents: Data())
        FileManager.default.createFile(atPath: module.appendingPathComponent("scripts/setup-runtime.sh").path, contents: Data())
        defer { try? FileManager.default.removeItem(at: base) }
        let found = DeepSeekSyncInstaller.locateModule(under: base)
        #expect(found?.lastPathComponent == "DeepSeekSync")
        // /var vs /private/var symlink prefix differs; compare the suffix.
        #expect(found?.path.hasSuffix("/APIMeter-1.2.2/DeepSeekSync") == true)
    }

    @Test func locateModuleIgnoresIncompleteDirectories() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds-test-" + UUID().uuidString, isDirectory: true)
        let module = base.appendingPathComponent("APIMeter-1.2.2/DeepSeekSync", isDirectory: true)
        try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
        // package.json only - missing launcher and setup script -> not a module.
        FileManager.default.createFile(atPath: module.appendingPathComponent("package.json").path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(DeepSeekSyncInstaller.locateModule(under: base) == nil)
    }

    @Test func moduleDestinationIsUnderApplicationSupport() {
        let dest = DeepSeekSyncInstaller.moduleDestination()
        #expect(dest.lastPathComponent == "DeepSeekSync")
        #expect(dest.path.contains("Application Support"))
    }

    @MainActor
    @Test func dismissedSetupPromptPersists() throws {
        let suite = "ds-settings-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults)
        #expect(first.dismissedSyncSetupPrompt == false)
        first.dismissedSyncSetupPrompt = true
        let second = AppSettings(defaults: defaults)
        #expect(second.dismissedSyncSetupPrompt == true)
    }
}
