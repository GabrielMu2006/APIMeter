# Phase A - Technical Validation Report

Date: 2026-08-17 (UTC+8)
Environment: macOS 26.3.1 (arm64), Xcode 26.6, Swift 6.3.3, SDK macosx26.5, deployment target macOS 15

## Results

| Item | Result | Notes |
|------|--------|-------|
| Balance API (implementation + official schema) | PASS | Client built and unit-tested against the official documented schema (GET /user/balance, balance_infos with string amounts). LIVE call against the real account is PENDING the user's API key. |
| Keychain | PASS | SecItem generic-password roundtrip verified (selfcheck + 3 tests). Idempotent save, delete, list. |
| CSV Import (pipeline PoC) | PASS (pipeline) / PENDING (real schema) | RFC4180 parser (scalar-safe CRLF), ZIP extraction, schema DETECTOR (analysis only - no guessing), file+row dedup all verified. The DeepSeek official mapper is intentionally NOT written until a real export is analyzed. |
| CSV actual schema | PENDING | Awaiting a real export file. docs/deepseek-csv-schema.md is a template. |
| Daily granularity | PENDING | Depends on the real CSV. |
| API Key granularity | PENDING | Depends on the real CSV. |
| Request count | PENDING | Depends on the real CSV. |
| Token data | PENDING | Depends on the real CSV. |
| Model data | PENDING | Depends on the real CSV. |
| Historical daily dashboard | SUPPORTED (internally verified) | Day-bucketed aggregation, official-over-estimated reconciliation, Decimal exactness, key filtering all pass 37 unit tests + 14 selfchecks with clearly labeled synthetic fixtures. Displaying REAL history needs the real CSV. |
| Local Gateway feasibility | LOW risk | PoC verified end-to-end with a mock upstream: non-stream relay byte-identical to direct call, SSE streaming relayed line-by-line (no full buffering), usage (tokens + requests) recorded into SQLite, port-conflict detection with the exact spec message, 127.0.0.1 only. Same-second requests do not collapse. |
| Local Gateway necessity | To be decided after CSV analysis | If the export is daily per key: LOW (gateway only for intra-day realtime). If it lacks daily granularity: HIGH. |

## Key findings / engineering notes

1. GRDB does not manage PRAGMA user_version - the app mirrors the migration version into user_version explicitly (spec 102).
2. Money is stored as exact decimal TEXT; aggregation in Swift with Decimal (never Double).
3. Day buckets are computed once at import in the local timezone; timezone changes cannot corrupt history.
4. Official CSV overrides gateway estimates per day - never summed (verified by tests).
5. Swift Character iteration silently merges CRLF into one grapheme - the CSV parser iterates Unicode scalars.
6. Row hashes include fractional-second timestamps so two gateway requests in the same second stay distinct.
7. Gateway pricing estimation is disabled until price_rules are seeded; without rules the cost column is honestly nil.
8. ZIP extraction uses the system ditto binary (no extra dependency).
9. SPM-only for Phase A; the Xcode .app target (MenuBarExtra/NSPanel needs a bundle) is a Phase B step.
10. Toolchain quirk: the session shell had a broken PATH/HOME; builds run with an explicit clean environment.

## Deviations from PROJECT_SPEC.md (justified, non-breaking)

1. usage_records.amount is TEXT (exact decimal string), not REAL - spec 105 mandates Decimal and forbids Double; REAL would corrupt money. Aggregation happens in Swift, not SQL SUM.
2. balance_snapshots gains an is_available column (needed to restore last-known balance state per spec 81).
3. price_rules gains a provider column (spec 29 lists it).
4. UsageImportService takes a pluggable CSVMapper protocol; no DeepSeek mapper exists until the real file is analyzed (spec 14/117).
5. Local gateway forwards via URLSession instead of SwiftNIO client channels - simpler, same transparency guarantees; NIO is still the server.

## Current risks

- Risk 1 (CSV schema): still the highest unknown - blocked on a real export.
- Risk 2 (daily granularity): blocked on the same file.
- Streaming first-token latency with URLSession.AsyncBytes was not benchmarked against a real DeepSeek stream (mock only); target is < 5 ms added overhead - to be measured in Phase A.4 live test.
- Keychain prompts for an unsigned CLI differ from the signed app bundle; final app must migrate/verify access.

## Next phase recommendation

1. Obtain the two missing inputs: (a) a DeepSeek API key at ~/.apimeter_dev_key.txt for the live balance test, (b) one real Usage Export ZIP/CSV for schema analysis.
2. After (b): fill docs/deepseek-csv-schema.md from the detector output, implement the DeepSeek mapper, run the real import, and print the first 30-day daily table from real data.
3. Then proceed to Phase B (MenuBarExtra + dashboard + Swift Charts + CSV import UI) exactly per spec 114 Step 6-7.
4. Gateway stays experimental (spec 93) until Phase C.
