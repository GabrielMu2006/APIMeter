# API Meter

Native macOS menu bar + floating dashboard for DeepSeek API usage.

## Status

- [x] Phase A - technical validation (complete)
  - Balance API live: PASS (real key, real balance)
  - CSV schema documented from real exports (docs/deepseek-csv-schema.md)
  - 43 unit tests passing
- [x] Phase B - MVP (complete)
  - MenuBarExtra quick panel: balance, today, 7-day mini trend, top keys
  - Dashboard: metric cards, 7D/30D/Month/Custom ranges, Swift Charts trend,
    daily history with per-day detail, multi-select API key filter
  - Settings: DeepSeek key (Keychain only), key aliases, data import/clear
  - CSV import UI: file picker + drag & drop (ZIP and CSV)
  - Real data: 8 official days, 20.13 CNY, 1067 requests, 5 named keys
  - Per-key cost DERIVED from official price x amount rows, cross-checked
    against billing totals at import (mismatch -> estimated, never guessed)
- [ ] Phase C - full V1 (NSPanel pin, mini mode, notifications, gateway stable)
- [ ] Phase C+ - open source prep

## Build & run

```bash
# Core library + validation CLI + tests (SwiftPM)
swift build
swift test
.build/debug/apimeter selfcheck

# The macOS app (Xcode project)
xcodebuild -project APIMeter.xcodeproj -scheme APIMeter \
  -configuration Debug -derivedDataPath .build/DerivedData build
open ".build/DerivedData/Build/Products/Debug/API Meter.app"
```

Or open `APIMeter.xcodeproj` in Xcode and press Run.

## Layout

```
APIMeter/            app + core sources (Xcode app target + SPM library)
  App/               SwiftUI entry, AppState, AppEnvironment
  Models/            Balance, APIKey, UsageRecord, DailyUsage, ...
  DeepSeek/          balance client
  Security/          KeychainService, KeyFingerprint
  Database/          GRDB manager, migration v1, row structs
  Import/            CSV parser, schema detector, official mapper, dedup
  Usage/             repository, aggregator, reconciler, pricing
  Gateway/           local gateway (127.0.0.1 only) - experimental
  UI/                MenuBar, Dashboard, History, Settings views
  ViewModels/        Balance/Dashboard/Settings view models
Tools/PhaseAValidator   validation CLI (apimeter)
Tools/mock-upstream.py  dev-only mock DeepSeek server
Tests/               43 unit tests
docs/                 schema + phase reports (samples are gitignored)
```

## Data sources

1. DeepSeek Balance API - current balance (Keychain key).
2. Official DeepSeek Usage Export (ZIP/CSV) - historical truth.
3. Optional local gateway on 127.0.0.1:43123 - realtime estimates.

Official CSV always overrides gateway estimates for the same day.

## Security rules (from PROJECT_SPEC.md)

- API keys only in macOS Keychain; SQLite stores SHA256 fingerprints only.
- No browser cookie reading, no Usage page scraping, no HTTPS MITM.
- Gateway listens on 127.0.0.1 only, never 0.0.0.0.
- Logs never contain keys, prompts, completions or cookies.
