# Contributing

## Build

```bash
swift build && swift test
xcodebuild -project APIMeter.xcodeproj -scheme APIMeter \
  -configuration Debug -derivedDataPath .build/DerivedData build
```

## DeepSeekSync

```bash
cd DeepSeekSync && ./scripts/setup-runtime.sh
```

## Rules

- Never commit secrets: no API keys, no sessions, no account identifiers.
  Real usage exports belong in docs/samples/ (gitignored).
- Database changes require a migration (GRDB migrator, PRAGMA user_version).
- Tests are required for aggregation, import/dedup, pricing and scheduling logic.