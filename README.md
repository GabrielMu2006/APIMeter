# API Meter

Native macOS menu bar + floating dashboard for DeepSeek API usage.

## Features

- Menu bar quick panel: balance, today, 7-day trend, top API keys
- Floating dashboard: metric cards, 7D/30D/Month/Custom ranges, bar chart
  with per-day per-key tooltip, daily history with day detail
- Per-key cost derived from official price x amount rows, cross-checked
  against billing totals (replace semantics - no double counting)
- Today = balance-delta estimate with top-up detection (official exports
  are authoritative for completed days)
- Daily export sync at 00:30 via the bundled DeepSeekSync (Playwright,
  Keychain session, never stores credentials)
- Balance alerts with anti-spam state machine, launch at login, global
  shortcut, dock icon toggle, light/dark, macOS 26 glass

## Data sources

1. DeepSeek Balance API - current balance (Keychain key).
2. Official DeepSeek Usage Export (ZIP/CSV) - historical truth.
3. Balance-derived estimate - today only, with top-up detection.

## Build

```bash
swift build && swift test
xcodebuild -project APIMeter.xcodeproj -scheme APIMeter \
  -configuration Release -derivedDataPath .build/DerivedData-Release build
```

## Security & privacy

- API keys only in the macOS Keychain; SQLite stores SHA256 fingerprints only.
- No browser cookie reading, no Usage page scraping beyond the official
  export button (see PROJECT_SPEC.md DR-001), no HTTPS MITM.
- Logs never contain keys, prompts, completions or cookies.
- See PRIVACY.md for details.

## Layout

```
APIMeter/            app + core sources
Tools/PhaseAValidator   validation CLI (apimeter)
DeepSeekSync/        Playwright export downloader (standalone)
Tests/               Swift Testing unit tests
docs/                schema + phase reports (samples gitignored)
```