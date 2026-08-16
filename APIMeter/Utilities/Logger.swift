import Foundation
import os

/// Central logger. SECURITY: never log API keys, authorization headers,
/// prompts, completions, cookies or raw request bodies (spec §86).
/// All messages are sanitized before hitting the OS log.
public enum Log {
    private static let logger = Logger(subsystem: "com.apimeter", category: "app")

    private static let keyPattern = try! NSRegularExpression(pattern: "sk-[A-Za-z0-9_-]{8,}")

    public static func sanitize(_ message: String) -> String {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return keyPattern.stringByReplacingMatches(in: message, range: range, withTemplate: "sk-***")
    }

    public static func info(_ message: String) {
        let safe = sanitize(message)
        logger.info("\(safe, privacy: .public)")
    }

    public static func error(_ message: String) {
        let safe = sanitize(message)
        logger.error("\(safe, privacy: .public)")
    }

    public static func debug(_ message: String) {
        let safe = sanitize(message)
        logger.debug("\(safe, privacy: .public)")
    }
}
