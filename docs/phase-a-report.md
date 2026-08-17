# Phase A - Technical Validation Report

Date: 2026-08-17 (UTC+8)
Environment: macOS 26.3.1 (arm64), Xcode 26.6, Swift 6.3.3, SDK macosx26.5, deployment target macOS 15

## Final results (all live validations completed)

| Item | Result | Evidence |
|------|--------|----------|
| Balance API | PASS | Real key from Keychain -> GET /user/balance -> CNY total=25.02, granted=0.00, topped_up=25.02, is_available=true. Snapshot persisted to SQLite. (Balance moved 25.93 -> 25.02 during the session - the account is live.) |
| Keychain | PASS | SecItem roundtrip verified (selfcheck + tests). Key saved from a 0600 temp file that was deleted after saving. |
| CSV Import | PASS | Both real export files imported: 10 cost rows -> 10 records, 55 amount rows -> 14 grouped records. Re-import correctly rejected (file-level dedup). |
| CSV actual schema | DOCUMENTED | docs/deepseek-csv-schema.md written from the real files. Two-file format (amount + cost), long-format type rows, masked api keys. |
| Daily granularity | YES | Day buckets at 00:00:00+08:00 (end exclusive) in both files. |
| API Key granularity | YES (quantities) / NO (cost) | api_key_name + masked api_key in the amount file; the cost file has no key dimension. |
| Request count | YES | type=request_count rows in the amount file. |
| Token data | YES | input_cache_hit/miss + output tokens; total computed as the sum (no total column). |
| Model data | YES | deepseek-v4-pro, deepseek-v4-flash. |
| Historical Daily Dashboard | SUPPORTED | 8 official days aggregated from real data: total 20.13 CNY, 1067 requests, 139,356,082 tokens - verified against the raw CSV sums. |
| Local Gateway feasibility | LOW RISK | Mock-upstream PoC passed: byte-identical non-stream relay, SSE passthrough, usage recorded, port-conflict detection. |
| Local Gateway necessity | LOW for history / MEDIUM for per-key cost | Official export is daily-grained, so history is fully covered by CSV. Per-key COST is not provided by the export - only the gateway can estimate it. |

## Real schema findings (the important surprises)

1. The export is TWO files: amount (quantities) and cost (money) - not one combined CSV.
2. The amount file is LONG format: one row per (day, model, key, type).
3. api_key is MASKED by DeepSeek (sk-92063****e267). The masked string is the stable per-key identity; api_key_name is the display name.
4. The cost file attributes money per (day, model) only - per-key cost is officially unavailable.
5. Timestamps carry +08:00; the billing day = the date in that offset (stable regardless of the Mac's timezone).
6. price column carries official per-token prices -> seeded into price_rules (no hardcoded prices).

## Verified with real data

- 8 daily rows with verification=official, costs matching the raw CSV exactly.
- 5 real API keys with official names: deerflow, Codex, opencode, Hermes, harness.
- Official CSV overrides gateway estimates per day (unit tested + the rule design).
- Decimal money math exact across 1000-row synthetic test and the real totals.

## Engineering notes

- Aggregator rule refined after real data: a metric is the sum of what records
  provide it (cost rows carry no tokens, quantity rows carry no money); nil only
  when nothing provides it. The earlier any-row-missing rule would have zeroed
  every day's cost.
- GRDB does not manage PRAGMA user_version; mirrored explicitly (spec 102).
- Swift Character iteration merges CRLF into one grapheme - CSV parser iterates
  Unicode scalars.
- Row hashes include fractional-second timestamps (same-second gateway requests
  stay distinct).
- Money stored as exact decimal TEXT, aggregation in Swift Decimal (never Double).
- Day buckets computed once at import; timezone changes cannot corrupt history.

## Deviations from PROJECT_SPEC.md (all justified, none core)

1. usage_records.amount is TEXT (exact decimal), not REAL - spec 105 forbids Double for money.
2. balance_snapshots gains is_available (restore last-known state, spec 81).
3. price_rules gains provider (spec 29 lists it).
4. Gateway forwards via URLSession; SwiftNIO is the server (simpler, same transparency).
5. Per-key cost from official data is impossible (export limitation) - displayed as unknown per spec 119.

## Addendum (2026-08-17, post-Phase-B review)

The report's earlier claim "per-key cost is officially unavailable" was
WRONG. The amount file carries price AND quantity per row; sum(price x amount)
per (day, model, key) reproduces the cost file exactly (verified against all
14 groups: total 20.126657 matches to the last digit). Phase B implements:
derived per-key cost + import-time reconciliation against billing totals +
billing-authoritative day totals (no double counting).

## Next phase recommendation

Phase A is complete: Balance PASS, Keychain PASS, CSV PASS, daily aggregation verified on real data,
gateway feasibility proven. Proceed to Phase B (spec 93): MenuBarExtra, current balance, today usage,
7D/30D/month views, daily history, Swift Charts, API key filter, CSV import UI, SQLite+Keychain integration.
Gateway stays experimental until Phase C.
