# API Meter

Native macOS menu bar + floating dashboard for DeepSeek API usage.

## Status

- [x] Phase A - technical validation (in progress)
  - [x] Swift 6 / macOS 15+ package scaffold (SPM; Xcode app target in Phase B)
  - [x] KeychainService + SHA256 fingerprint
  - [x] DeepSeek Balance API client (validated against official docs schema)
  - [ ] Balance API live validation (awaiting user API key)
  - [x] CSV import pipeline PoC (parser / schema detector / dedup / ZIP)
  - [ ] Real DeepSeek usage export analysis (awaiting real file)
  - [x] SQLite via GRDB, migration v1, UsageRepository, daily aggregation
  - [x] Local gateway PoC: 127.0.0.1 only, non-stream + streaming relay, usage collection
  - [x] Unit tests: 37 passing
- [ ] Phase B - MVP (MenuBarExtra, dashboard, CSV import UI)
- [ ] Phase C - full V1 (NSPanel, mini mode, notifications, settings)
- [ ] Phase C+ - open source prep

## Build

```bash
swift build
swift test
.build/debug/apimeter selfcheck
```

## Data sources

1. DeepSeek Balance API (`GET https://api.deepseek.com/user/balance`) - current balance.
2. Official DeepSeek Usage Export (ZIP/CSV) - historical truth.
3. Optional local gateway on 127.0.0.1:43123 - realtime estimates.

Official CSV always overrides gateway estimates for the same day.

## Security rules (from PROJECT_SPEC.md)

- API keys only in macOS Keychain; SQLite stores SHA256 fingerprints only.
- No browser cookie reading, no Usage page scraping, no HTTPS MITM.
- Gateway listens on 127.0.0.1 only, never 0.0.0.0.
- Logs never contain keys, prompts, completions or cookies.
