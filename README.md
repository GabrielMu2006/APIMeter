# API Meter

Native macOS menu bar + floating dashboard for DeepSeek API usage.

## Status

- [x] Phase A - technical validation (complete)
- [x] Phase B - MVP (complete)
- [x] Phase C - full V1 (complete)
  - Floating NSPanel dashboard: pin (floating level), mini mode, window
    state restore (position/size/pin/mini)
  - Mini panel: balance + today only, draggable, right-click actions,
    double-click to expand
  - Global shortcut (default Option+Space, recorder in Settings)
  - Launch at Login (SMAppService), Dock icon toggle
  - Balance alert with threshold + anti-spam state machine
  - Adaptive refresh (5 min visible / 15 min background) + sleep/wake
  - History retention (30D/90D/1Y/Forever) + CSV export
  - Appearance System/Light/Dark + macOS 26 Liquid Glass buttons
  - Gateway settings (stable optional feature, 127.0.0.1 only)
  - Settings: General/DeepSeek/API Keys/Usage/Notifications/Gateway/
    Appearance/Data/About
- [ ] Phase C+ - open source prep (docs, CI, full test matrix)

## Verified with real data (this account)

- Balance via official API (Keychain key)
- Official exports imported: 8 days, 20.13 CNY, 1067 requests,
  139,356,082 tokens, 5 named keys
- Per-key cost derived from official price x amount rows and
  cross-checked against billing totals (exact match)
- 54 unit tests passing

## Build & run

```bash
swift build && swift test
.build/debug/apimeter selfcheck

xcodebuild -project APIMeter.xcodeproj -scheme APIMeter \
  -configuration Debug -derivedDataPath .build/DerivedData build
open ".build/DerivedData/Build/Products/Debug/API Meter.app"
```

Or open `APIMeter.xcodeproj` in Xcode and press Run.

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
