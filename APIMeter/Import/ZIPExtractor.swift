import Foundation

public enum ZIPExtractor {
    public static let maxExtractedFileBytes: Int64 = 64 * 1024 * 1024
    public static let maxExtractedTotalBytes: Int64 = 256 * 1024 * 1024

    /// Extracts a ZIP with the system ditto into a fresh temporary directory
    /// and returns the .csv files found plus the temp dir (the caller MUST
    /// remove it - review P1: no leaked scratch dirs).
    /// Decompressed size is capped (the 100MB check alone only covers the
    /// compressed payload, review P1: zip-bomb guard).
    public static func extract(zipURL: URL) throws -> (files: [URL], tempDir: URL) {
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
            try? fm.removeItem(at: dest)
            throw ImportError.zipExtractionFailed(message)
        }

        let urls = (fm.enumerator(at: dest, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
        let csvFiles = urls.filter { $0.pathExtension.lowercased() == "csv" }
        guard csvFiles.count <= 100 else {
            try? fm.removeItem(at: dest)
            throw ImportError.tooManyFiles(csvFiles.count)
        }
        var total: Int64 = 0
        for file in csvFiles {
            let size = ((try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value) ?? 0
            if size > maxExtractedFileBytes {
                try? fm.removeItem(at: dest)
                throw ImportError.fileTooLarge(size)
            }
            total += size
        }
        if total > maxExtractedTotalBytes {
            try? fm.removeItem(at: dest)
            throw ImportError.fileTooLarge(total)
        }
        return (csvFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }, dest)
    }
}
