import Foundation
import Testing
import APIMeterCore

/// Integration tests for the atomic ZIP import pipeline (review P1).
struct ImportPipelineTests {

    private func csv(_ header: [String], _ rows: [[String]]) -> Data {
        var lines = [header.joined(separator: ",")]
        lines.append(contentsOf: rows.map { $0.joined(separator: ",") })
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func makeZip(files: [String: Data]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-meter-zip-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: dir.appendingPathComponent(name))
        }
        let zip = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-meter-zip-test-" + UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: dir) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", dir.path, zip.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ImportError.zipExtractionFailed("ditto failed") }
        return zip
    }

    private func setup() throws -> (UsageRepository, UsageImportService) {
        let db = try DatabaseManager.ephemeral()
        return (UsageRepository(database: db), UsageImportService(repository: UsageRepository(database: db)))
    }

    @Test func zipImportIsAtomicOnFailure() async throws {
        let (repo, service) = try setup()
        let amount = csv(
            ["user_id", "start_time_iso", "end_time_iso", "model", "api_key_name", "api_key", "type", "price", "amount"],
            [["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "K", "sk-1", "request_count", "", "5"]]
        )
        // Second file has an unknown type -> mapper throws during PREPARE.
        let bad = csv(
            ["user_id", "start_time_iso", "end_time_iso", "model", "api_key_name", "api_key", "type", "price", "amount"],
            [["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "K", "sk-1", "future_type", "", "1"]]
        )
        let zip = try makeZip(files: ["amount.csv": amount, "bad.csv": bad])
        defer { try? FileManager.default.removeItem(at: zip) }

        do {
            _ = try await service.importFile(at: zip, mapper: DeepSeekOfficialCSVMapper())
            Issue.record("expected the import to fail")
        } catch {
            // expected
        }
        // NOTHING was written (the atomic guarantee).
        #expect(try repo.recordCount() == 0)
        #expect(try repo.fetchImportBatches().isEmpty)
    }

    @Test func zipImportSucceedsWithBothKinds() async throws {
        let (repo, service) = try setup()
        let amount = csv(
            ["user_id", "start_time_iso", "end_time_iso", "model", "api_key_name", "api_key", "type", "price", "amount"],
            [
                ["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "K", "sk-1", "request_count", "", "5"],
                ["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "K", "sk-1", "output_tokens", "0.000006", "1000"],
            ]
        )
        let cost = csv(
            ["user_id", "start_time_iso", "end_time_iso", "model", "wallet_type", "cost", "currency"],
            [["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "Paid", "0.006", "CNY"]]
        )
        let zip = try makeZip(files: ["amount.csv": amount, "cost.csv": cost])
        defer { try? FileManager.default.removeItem(at: zip) }

        let result = try await service.importFile(at: zip, mapper: DeepSeekOfficialCSVMapper())
        #expect(result.filesImported == 2)
        #expect(result.inserted >= 2)
        #expect(try repo.recordCount() >= 2)
        #expect(try repo.fetchImportBatches().count == 2)
    }

    @Test func zipWithAlreadyImportedFileSkipsIt() async throws {
        let (repo, service) = try setup()
        let amount = csv(
            ["user_id", "start_time_iso", "end_time_iso", "model", "api_key_name", "api_key", "type", "price", "amount"],
            [["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "K", "sk-1", "request_count", "", "5"]]
        )
        let cost = csv(
            ["user_id", "start_time_iso", "end_time_iso", "model", "wallet_type", "cost", "currency"],
            [["a", "2026-08-17T00:00:00+08:00", "2026-08-18T00:00:00+08:00", "m", "Paid", "0.006", "CNY"]]
        )
        let zip = try makeZip(files: ["amount.csv": amount, "cost.csv": cost])
        defer { try? FileManager.default.removeItem(at: zip) }

        _ = try await service.importFile(at: zip, mapper: DeepSeekOfficialCSVMapper())
        // Second import: both sub-files already imported -> duplicate error
        // (not a stuck partial state), and nothing changed.
        do {
            _ = try await service.importFile(at: zip, mapper: DeepSeekOfficialCSVMapper())
            Issue.record("expected duplicate")
        } catch let error as ImportError {
            if case .duplicateFile = error {
                // expected
            } else {
                let message = error.errorDescription ?? "unknown"
Issue.record("unexpected error: \(message)")
            }
        }
        #expect(try repo.recordCount() >= 2)
    }
}
