# DeepSeekSync

Automated DeepSeek Usage Export downloader (standalone CLI).

Status: VERIFIED end-to-end (2026-08-17) - login, hidden-mode sync,
download, and the API Meter import pipeline (incremental + dedup) all pass.

- Playwright + persistent Chromium profile (module-owned, never touches your browsers)
- Session (cookies + localStorage) stored encrypted in the macOS Keychain via the system `security` tool
- Never stores your DeepSeek username or password
- No unpublished/internal APIs; drives only the official Usage page
- Downloads go to ~/Library/Application Support/DeepSeekSync/downloads/

## Setup (once)

```bash
./scripts/setup-runtime.sh   # bundles Node, installs Playwright + Chromium
```

## First run

```bash
./deepseek-sync login   # a browser window opens - sign in by hand (any captcha/MFA)
```

## Sync (daily, headless)

```bash
./deepseek-sync sync    # opens Usage, selects near 30 days, clicks Export, downloads
./deepseek-sync status  # session + last sync info
./deepseek-sync dump    # debug: print page buttons/links
./deepseek-sync logout  # remove the saved session
```

Session expired? The sync prints `DeepSeek session expired. Please login again.`
- run login again.