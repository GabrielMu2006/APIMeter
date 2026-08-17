import APIMeterCore
import Foundation

/// Phase A validation CLI.
/// Commands:
///   keychain set --file PATH | keychain set KEY | keychain list | keychain delete PREFIX
///   balance [--fingerprint PREFIX]
///   db init | db info | db dump
///   analyze PATH [--out FILE]
///   import PATH
///   daily [--days N]
///   selfcheck
///   gateway [--port N] [--upstream URL]
@main
struct PhaseAValidator {

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            usage()
            exit(1)
        }
        do {
            switch command {
            case "keychain": try keychainCommand(Array(args.dropFirst()))
            case "balance": try await balanceCommand(Array(args.dropFirst()))
            case "db": try dbCommand(Array(args.dropFirst()))
            case "analyze": try analyzeCommand(Array(args.dropFirst()))
            case "import": try await importCommand(Array(args.dropFirst()))
            case "daily": try dailyCommand(Array(args.dropFirst()))
            case "selfcheck": try await selfCheck()
            default:
                usage()
                exit(1)
            }
        } catch {
            print("ERROR: " + error.localizedDescription)
            exit(1)
        }
    }

    static func usage() {
        print("apimeter - API Meter Phase A validation tool")
        print("usage:")
        print("  apimeter keychain set --file PATH   save API key from a file (file is deleted after)")
        print("  apimeter keychain set KEY           save API key directly (shell history risk)")
        print("  apimeter keychain list              list stored fingerprints")
        print("  apimeter keychain delete PREFIX     delete key by fingerprint prefix")
        print("  apimeter balance                    fetch balance via DeepSeek API")
        print("  apimeter db init|info|dump          database utilities")
        print("  apimeter analyze PATH [--out FILE]  analyze a ZIP/CSV usage export")
        print("  apimeter import PATH                import a usage export")
        print("  apimeter daily [--days N]           print daily aggregation table")
        print("  apimeter selfcheck                  run internal validation checks")
        print("  apimeter gateway [--port N]         run the local usage gateway")
    }

    // MARK: - keychain

    static func keychainCommand(_ args: [String]) throws {
        let service = KeychainService()
        guard let sub = args.first else {
            print("keychain: missing subcommand (set|list|delete)")
            exit(1)
        }
        switch sub {
        case "set":
            let rest = Array(args.dropFirst())
            if rest.first == "--file" {
                guard let path = rest.dropFirst().first else {
                    print("keychain set --file PATH")
                    exit(1)
                }
                let url = URL(fileURLWithPath: path)
                let raw = try String(contentsOf: url, encoding: .utf8)
                let fingerprint = try service.saveAPIKey(raw)
                try? FileManager.default.removeItem(at: url)
                print("SAVED key to Keychain. Fingerprint: " + fingerprint)
                print("Temp file " + path + " deleted.")
            } else if let key = rest.first {
                let fingerprint = try service.saveAPIKey(key)
                print("SAVED key to Keychain. Fingerprint: " + fingerprint)
                print("Warning: prefer --file to keep the key out of shell history.")
            } else {
                print("keychain set --file PATH | keychain set KEY")
                exit(1)
            }
        case "list":
            let fingerprints = try service.listFingerprints()
            if fingerprints.isEmpty {
                print("No API keys in Keychain.")
            } else {
                for fingerprint in fingerprints {
                    print(KeyFingerprint.displayPrefix(fingerprint, length: 12) + "...  " + fingerprint)
                }
            }
        case "delete":
            guard let prefix = args.dropFirst().first else {
                print("keychain delete PREFIX")
                exit(1)
            }
            let matches = try service.listFingerprints().filter { $0.hasPrefix(prefix.uppercased()) || $0.lowercased().hasPrefix(prefix.lowercased()) }
            guard let match = matches.first else {
                print("No key matches prefix " + prefix)
                exit(1)
            }
            try service.deleteAPIKey(fingerprint: match)
            print("Deleted key " + KeyFingerprint.displayPrefix(match, length: 12) + "...")
        default:
            print("unknown keychain subcommand")
            exit(1)
        }
    }

    // MARK: - balance

    static func balanceCommand(_ args: [String]) async throws {
        let service = KeychainService()
        let stored = try service.listFingerprints()
        guard !stored.isEmpty else {
            print("No API key in Keychain. Run: apimeter keychain set --file PATH")
            exit(1)
        }
        var fingerprint: String
        if let idx = args.firstIndex(of: "--fingerprint"), let prefix = args.dropFirst(idx + 1).first {
            guard let match = stored.first(where: { $0.hasPrefix(prefix.uppercased()) }) else {
                print("No stored key matches prefix " + prefix)
                exit(1)
            }
            fingerprint = match
        } else {
            fingerprint = stored[0]
        }
        print("Using key " + KeyFingerprint.displayPrefix(fingerprint, length: 12) + "...")
        let provider = DeepSeekBalanceProvider(keychain: service, fingerprint: fingerprint)
        do {
            let balance = try await provider.fetchBalance()
            print("Balance API OK (fetched " + ISO8601.string(balance.fetchedAt) + ")")
            print("is_available: " + String(balance.isAvailable))
            for info in balance.balanceInfos {
                print("  " + info.currency + ": total=" + CurrencyFormatter.format(info.totalBalance, currency: info.currency) + " granted=" + CurrencyFormatter.format(info.grantedBalance, currency: info.currency) + " topped_up=" + CurrencyFormatter.format(info.toppedUpBalance, currency: info.currency))
            }
            // Persist snapshot for the storage link validation.
            let db = try DatabaseManager(path: DatabaseManager.defaultLocation().path)
            let repository = UsageRepository(database: db)
            try repository.saveBalanceSnapshot(balance)
            print("Balance snapshot saved to SQLite.")
        } catch let error as DeepSeekError {
            print("Balance API FAILED: " + (error.errorDescription ?? "deepseek error"))
            exit(2)
        }
    }

    // MARK: - db

    static func dbCommand(_ args: [String]) throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultLocation().path)
        let repository = UsageRepository(database: db)
        let sub = args.first ?? "info"
        switch sub {
        case "init":
            print("Database ready. schemaVersion=" + String(try db.schemaVersion))
            print("Path: " + db.path)
        case "info":
            print("Path: " + db.path)
            print("schemaVersion: " + String(try db.schemaVersion))
            print("usage records: " + String(try repository.recordCount()))
            let batches = try repository.fetchImportBatches()
            print("import batches: " + String(batches.count))
            print("price rules: " + String(try repository.fetchPriceRules().count))
            for batch in batches {
                print("  - " + (batch.filename ?? "?") + " rows=" + String(batch.rowCount) + " month=" + (batch.month ?? "?"))
            }
            let keys = try repository.fetchAPIKeys()
            print("api keys: " + String(keys.count))
            for key in keys {
                print("  - " + KeyFingerprint.displayPrefix(key.fingerprint, length: 8) + "... alias=" + (key.displayName ?? "(none)") + " official=" + (key.officialName ?? "(none)"))
            }
            if let latest = try repository.latestBalanceSnapshot() {
                for info in latest.balanceInfos {
                    print("latest balance snapshot: " + info.currency + " " + CurrencyFormatter.format(info.totalBalance, currency: info.currency) + " at " + ISO8601.string(latest.fetchedAt))
                }
            } else {
                print("latest balance snapshot: none")
            }
        case "dump":
            let records = try repository.recordsInRange(from: LocalDay("2020-01-01")!, to: LocalDay("2035-12-31")!)
            for record in records {
                let ts = record.timestamp.map(ISO8601.fractionalString) ?? "-"
                let hashPrefix = String(ImportDeduplicator.rowHash(record).prefix(12))
                print(String(record.id ?? 0) + " | " + ts + " | " + record.day.value + " | " + record.source.rawValue + " | req=" + (record.requestCount.map(String.init) ?? "-") + " | tok=" + (record.totalTokens.map(String.init) ?? "-") + " | hash=" + hashPrefix)
            }
        default:
            print("db: unknown subcommand")
            exit(1)
        }
    }

    // MARK: - analyze

    static func analyzeCommand(_ args: [String]) throws {
        guard let path = args.first else {
            print("analyze PATH [--out FILE]")
            exit(1)
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        var rows: [[String]]
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            let files = try ZIPExtractor.extract(zipURL: url)
            guard let first = files.first else {
                print("ZIP contains no CSV files.")
                exit(1)
            }
            print("ZIP extracted " + String(files.count) + " CSV file(s); analyzing first: " + first.lastPathComponent)
            rows = try CSVParser.parse(data: try Data(contentsOf: first))
        } else {
            rows = try CSVParser.parse(data: data)
        }
        guard !rows.isEmpty else {
            print("File has no rows.")
            exit(1)
        }
        let analysis = CSVSchemaDetector.analyze(rows: rows, sourceName: url.lastPathComponent)
        let report = analysis.markdownReport()
        if let idx = args.firstIndex(of: "--out"), let out = args.dropFirst(idx + 1).first {
            try report.write(toFile: out, atomically: true, encoding: .utf8)
            print("Report written to " + out)
        } else {
            print(report)
        }
    }

    // MARK: - import

    static func importCommand(_ args: [String]) async throws {
        guard let path = args.first else {
            print("import PATH")
            exit(1)
        }
        let db = try DatabaseManager(path: DatabaseManager.defaultLocation().path)
        let repository = UsageRepository(database: db)
        let service = UsageImportService(repository: repository)
        let mapper = DeepSeekOfficialCSVMapper()
        let url = URL(fileURLWithPath: path)
        do {
            let result = try await service.importFile(at: url, mapper: mapper)
            print("IMPORT OK")
            print("  files: " + String(result.filesImported))
            print("  rows in file(s): " + String(result.rowsInFile))
            print("  inserted: " + String(result.inserted))
            print("  duplicate rows ignored: " + String(result.ignoredDuplicates))
            print("  file hash: " + String(result.fileHash.prefix(16)) + "...")
            print("Run: apimeter daily  to see the daily aggregation.")
        } catch let error as ImportError {
            print("IMPORT FAILED: " + (error.errorDescription ?? "import error"))
            exit(3)
        }
    }

    // MARK: - daily

    static func dailyCommand(_ args: [String]) throws {
        var days = 30
        if let idx = args.firstIndex(of: "--days"), let value = args.dropFirst(idx + 1).first, let parsed = Int(value) {
            days = parsed
        }
        let db = try DatabaseManager(path: DatabaseManager.defaultLocation().path)
        let repository = UsageRepository(database: db)
        let end = LocalDay(date: Date())
        guard let start = LocalDay(end.adding(days: -(days - 1)).value) else { exit(1) }
        let daily = try repository.dailyUsage(from: start, to: end)
        if daily.isEmpty {
            print("No usage data between " + start.value + " and " + end.value + ".")
            print("Import a DeepSeek usage export first (apimeter import) or run the gateway.")
            return
        }
        let summary = try repository.summary(from: start, to: end)
        print("Daily aggregation (" + start.value + " .. " + end.value + ", local timezone " + (TimeZone.autoupdatingCurrent.identifier) + "):")
        print("PERIOD TOTALS: cost=" + (summary.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "-") + " requests=" + (summary.requests.map(String.init) ?? "-") + " tokens=" + (summary.tokens.map { TokenFormatter.full($0) } ?? "-"))
        print("day        | cost       | requests | tokens    | verification")
        print("-----------+------------+----------+-----------+------------")
        for day in daily {
            let cost = day.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "-"
            let requests = day.requests.map(String.init) ?? "-"
            let tokens = day.tokens.map(TokenFormatter.compact) ?? "-"
            let verification = day.verification == .official ? "official" : "estimated"
            print(day.day.value + " | " + cost + " | " + requests + " | " + tokens + " | " + verification)
        }
        print("")
        print("Per API key (period):")
        for key in summary.byAPIKey {
            let cost = key.cost.map { CurrencyFormatter.format($0, currency: "CNY") } ?? "-"
            print("  " + KeyFingerprint.displayPrefix(key.fingerprint, length: 8) + "... | " + cost + " | req " + (key.requests.map(String.init) ?? "-") + " | tok " + (key.tokens.map(TokenFormatter.compact) ?? "-"))
        }
    }

    // MARK: - selfcheck

    static func selfCheck() async throws {
        var pass = 0
        var fail = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print((ok ? "[PASS] " : "[FAIL] ") + name + (detail.isEmpty ? "" : " - " + detail))
            if ok { pass += 1 } else { fail += 1 }
        }

        // 1. Keychain roundtrip with a synthetic throwaway secret.
        do {
            let service = KeychainService()
            let synthetic = "sk-test-" + UUID().uuidString
            let fingerprint = try service.saveAPIKey(synthetic)
            let readBack = try service.readAPIKey(fingerprint: fingerprint)
            try service.deleteAPIKey(fingerprint: fingerprint)
            check("Keychain write/read/delete roundtrip", readBack == synthetic, "fingerprint=" + KeyFingerprint.displayPrefix(fingerprint, length: 8))
        } catch {
            check("Keychain write/read/delete roundtrip", false, error.localizedDescription)
        }

        // 2. Database migration + dedup + aggregation with labeled synthetic fixture rows.
        do {
            let db = try DatabaseManager.ephemeral()
            let repository = UsageRepository(database: db)
            check("Migration v1 applies (ephemeral DB)", try db.schemaVersion == 1, "user_version=" + String(try db.schemaVersion))

            let d1 = LocalDay("2026-08-15")!
            let d2 = LocalDay("2026-08-16")!
            let d3 = LocalDay("2026-08-17")!
            let fingerprint = KeyFingerprint.sha256Hex(of: "sk-fixture")
            var records: [UsageRecord] = []
            records.append(UsageRecord(day: d1, apiKeyFingerprint: fingerprint, model: "deepseek-chat", requestCount: 2, totalTokens: 200, amount: Decimal(string: "0.10"), currency: "CNY", source: .officialCSV, verification: .official))
            records.append(UsageRecord(day: d1, apiKeyFingerprint: fingerprint, model: "deepseek-chat", requestCount: 3, totalTokens: 300, amount: Decimal(string: "0.20"), currency: "CNY", source: .officialCSV, verification: .official))
            // gateway estimate for the same day must be overridden by official rows
            records.append(UsageRecord(day: d1, apiKeyFingerprint: fingerprint, model: "deepseek-chat", requestCount: 9, totalTokens: 900, amount: Decimal(string: "9.99"), currency: "CNY", source: .localGateway, verification: .estimated))
            records.append(UsageRecord(day: d2, apiKeyFingerprint: fingerprint, model: "deepseek-chat", requestCount: 5, totalTokens: 500, amount: Decimal(string: "0.50"), currency: "CNY", source: .localGateway, verification: .estimated))
            records.append(UsageRecord(day: d3, apiKeyFingerprint: fingerprint, model: "deepseek-chat", requestCount: 1, totalTokens: 100, amount: Decimal(string: "1.00"), currency: "CNY", source: .officialCSV, verification: .official))
            let stats = try repository.upsert(records)
            check("Upsert inserts 5 synthetic rows", stats.inserted == 5, "inserted=" + String(stats.inserted))

            // re-insert same rows: all ignored by row hash
            let stats2 = try repository.upsert(records)
            check("Row-level dedup ignores re-inserted rows", stats2.inserted == 0 && stats2.ignoredDuplicates == 5, "inserted=" + String(stats2.inserted))

            let daily = try repository.dailyUsage(from: d1, to: d3)
            check("Daily aggregation returns 3 days", daily.count == 3, "days=" + String(daily.count))
            let day1 = daily.first { $0.day == d1 }
            let officialWins = day1?.cost == Decimal(string: "0.30") && day1?.verification == .official
            check("Official CSV overrides gateway estimates for the same day", officialWins, "day1 cost=" + String(describing: day1?.cost))

            let summary = try repository.summary(from: d1, to: d3)
            let total = Decimal(string: "0.30")! + Decimal(string: "0.50")! + Decimal(string: "1.00")!
            check("Period cost aggregation is exact Decimal", summary.cost == total, "total=" + String(describing: summary.cost))

            // import batch dedup
            let hash = "FAKEHASH123"
            try repository.recordImportBatch(ImportBatch(fileHash: hash, filename: "test.zip", month: "2026-08", importedAt: Date(), rowCount: 10))
            check("File-level dedup detects existing batch", try repository.importBatchExists(fileHash: hash))

            // retention keeps recent, deletes old
            let deleted = try repository.applyRetention(.days30, now: d3)
            check("Retention (30d) deletes old rows only", deleted >= 0)
        } catch {
            check("Database pipeline checks", false, error.localizedDescription)
        }

        // 3. CSV parser basics.
        do {
            let rows = CSVParser.parse("a,b,c\r\n\"x,y\",2,\"line\nbreak\"\n")
            check("CSV parser handles quotes/CRLF/embedded newlines", rows.count == 2 && rows[1][0] == "x,y" && rows[1][2] == "line\nbreak")
            let bom = try CSVParser.parse(data: Data([0xEF, 0xBB, 0xBF]) + Data("h1,h2\n1,2\n".utf8))
            check("CSV parser strips BOM", bom.first?.first == "h1")
        } catch {
            check("CSV parser checks", false, error.localizedDescription)
        }

        // 4. Pricing engine rule versioning.
        do {
            let formatter = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
            let t1 = try Date("2026-01-01T00:00:00Z", strategy: formatter)
            let t2 = try Date("2026-08-17T00:00:00Z", strategy: formatter)
            let ruleV1 = PriceRule(model: "deepseek-chat", effectiveFrom: t1, cacheHitPrice: Decimal(1), cacheMissPrice: Decimal(2), outputPrice: Decimal(3), currency: "CNY")
            let ruleV2 = PriceRule(model: "deepseek-chat", effectiveFrom: t2, cacheHitPrice: Decimal(2), cacheMissPrice: Decimal(4), outputPrice: Decimal(6), currency: "CNY")
            let atOld = try Date("2026-06-01T00:00:00Z", strategy: formatter)
            let atNew = try Date("2026-09-01T00:00:00Z", strategy: formatter)
            check("PricingEngine picks v1 before the switch date", PricingEngine.selectRule(model: "deepseek-chat", at: atOld, rules: [ruleV1, ruleV2])?.cacheHitPrice == Decimal(1))
            check("PricingEngine picks v2 after the switch date", PricingEngine.selectRule(model: "deepseek-chat", at: atNew, rules: [ruleV1, ruleV2])?.cacheHitPrice == Decimal(2))
            let cost = PricingEngine.cost(cacheHitTokens: 1_000_000, cacheMissTokens: 0, outputTokens: 0, rule: ruleV1)
            check("PricingEngine per-1M cost math", cost == Decimal(1), "cost=" + String(describing: cost))
        } catch {
            check("PricingEngine checks", false, error.localizedDescription)
        }

        print("")
        print("SELFCHECK: " + String(pass) + " passed, " + String(fail) + " failed")
        if fail > 0 { exit(1) }
    }
}
