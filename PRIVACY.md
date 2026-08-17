# Privacy

API Meter is a local-first macOS app. All data stays on your Mac.

## What API Meter stores

- DeepSeek API key: macOS Keychain only (never in the database, preferences, or logs).
- Usage history: local SQLite database in ~/Library/Application Support/APIMeter/.
- Balance snapshots: same local database.
- DeepSeekSync session (if used): macOS Keychain, encrypted at rest by the OS.

## What API Meter never does

- Never uploads usage data, balances, or account information anywhere.
- Never collects prompts or completions.
- Never reads your browser cookies or browsing history.
- Never stores your DeepSeek password.
- Never uses HTTPS interception or installs certificates.

## What goes over the network

- GET https://api.deepseek.com/user/balance - with your API key, to fetch the balance.
- DeepSeekSync (optional): opens the official platform.deepseek.com usage page
  in its own browser profile to download the official usage export.

## Deleting everything

Remove the app, delete ~/Library/Application Support/APIMeter/ and
~/Library/Application Support/DeepSeekSync/, and delete the Keychain items
named com.apimeter.deepseek-api-keys and com.apimeter.deepseeksync
(Keychain Access app, or the Security command line tool).