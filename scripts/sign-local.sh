#!/bin/zsh
# Signs a built API Meter.app bundle with the local Apple Development
# identity so foreign keychain items (Qoder Safe Storage) keep their
# "Always Allow" ACL grant across rebuilds - ad-hoc binaries change
# identity every build and re-prompt. No-op when no identity exists, so
# this stays safe on machines without one. Usage:
#   scripts/sign-local.sh "/path/to/API Meter.app"
set -e
APP_BUNDLE="${1:?usage: sign-local.sh /path/to/API Meter.app}"

HASH=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')
if [[ -z "$HASH" ]]; then
  echo "sign-local: no Apple Development identity - leaving bundle ad-hoc signed"
  exit 0
fi
codesign --force --deep --sign "$HASH" "$APP_BUNDLE"
echo "sign-local: signed with identity $HASH"
