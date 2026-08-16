import CryptoKit
import Foundation

/// Two-level deduplication (spec 16/17):
/// - file level: SHA256 of the whole file -> import_batches
/// - row level:  SHA256 of canonicalized row content -> usage_records.source_row_hash
public enum ImportDeduplicator {

    public static func fileHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    /// Stable canonical row hash. Fields the source does not provide become empty
    /// strings, so overlapping exports of the same logical row collide correctly.
    public static func rowHash(_ record: UsageRecord) -> String {
        let parts: [String] = [
            record.day.value,
            record.timestamp.map(ISO8601.fractionalString) ?? "",
            record.apiKeyFingerprint ?? "",
            record.model ?? "",
            record.requestCount.map(String.init) ?? "",
            record.cacheHitTokens.map(String.init) ?? "",
            record.cacheMissTokens.map(String.init) ?? "",
            record.inputTokens.map(String.init) ?? "",
            record.outputTokens.map(String.init) ?? "",
            record.totalTokens.map(String.init) ?? "",
            record.amount.map(DecimalStorage.string) ?? "",
            record.currency ?? "",
            record.source.rawValue,
        ]
        let canonical = parts.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02X", $0) }.joined()
    }
}
