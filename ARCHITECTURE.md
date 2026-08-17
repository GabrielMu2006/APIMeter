# Architecture

Native macOS 15+ menu bar app (Swift 6, SwiftUI + AppKit), layered as:

```
UI (SwiftUI: MenuBar / Dashboard / MiniPanel / Settings)
  -> ViewModels (@MainActor @Observable)
  -> AppEnvironment (composition root)
  -> UsageRepository / BalanceProvider / ImportService / SyncScheduler
  -> SQLite (GRDB, migration v1+) | macOS Keychain | DeepSeek API
```

## Data sources and trust order

1. Official DeepSeek Usage Export (ZIP/CSV) - authoritative billing history.
   Imported with REPLACE semantics per (day, model, api key): the export's
   day buckets are cumulative snapshots, a newer import supersedes older
   totals for the same bucket (prevents double counting).
2. DeepSeek Balance API - current balance; snapshots stored on every refresh.
   Today's cost is a balance-delta estimate (yesterday's last baseline minus
   today, ignoring increases as top-ups; 24h baseline guard).
3. Optional DeepSeekSync module - Playwright-based downloader of the official
   export, scheduled once per day at 00:30 by the app; stores its session in
   the Keychain, never credentials.

## Key modules

- APIMeter/ - app + core (also builds as the APIMeterCore SPM library + CLI).
- Tools/PhaseAValidator - validation CLI (apimeter).
- DeepSeekSync/ - standalone Node/Playwright export downloader (bundled
  Node runtime, gitignored).
- Tests/ - 64 Swift Testing unit tests.

## Invariants

- Money is Decimal (TEXT storage), tokens are Int64, timestamps UTC,
  day buckets local-timezone computed once at import.
- Official rows override estimates for the same day.
- Per-key cost is derived from official price x amount rows and
  cross-checked against billing totals at import.
- Secrets live only in the Keychain; logs are redacted (sk-***).