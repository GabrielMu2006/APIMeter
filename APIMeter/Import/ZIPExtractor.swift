import Foundation

public enum ZIPExtractor {

    /// Extracts a ZIP with the system ditto into a fresh temporary directory
    /// and returns all .csv files found inside (sorted by name).
    /// ditto is present on every macOS and handles the formats DeepSeek exports.
    public static func extract(zipURL: URL) throws -> [URL] {
        let fm = FileManager.default
        let dest = fm.temporaryDirectory
            .appendingPathComponent("APIMeter-import-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, dest.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ImportError.zipExtractionFailed(message)
        }

        let urls = (fm.enumerator(at: dest, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
        let csvFiles = urls.filter { $0.pathExtension.lowercased() == "csv" }
        guard csvFiles.count <= 100 else { throw ImportError.tooManyFiles(csvFiles.count) }
        return csvFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
