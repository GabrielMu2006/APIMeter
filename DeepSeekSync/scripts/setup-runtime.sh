#!/bin/sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"
echo "[1/3] checking bundled Node runtime..."
NODE_BIN="$SCRIPT_DIR/runtime/node-v24.19.0-darwin-arm64/bin/node"
if [ ! -x "$NODE_BIN" ]; then
  echo "  downloading Node v24.19.0 (portable, ~50MB)..."
  mkdir -p runtime
  curl -sSL -o /tmp/node-v24.19.0-darwin-arm64.tar.gz https://nodejs.org/dist/v24.19.0/node-v24.19.0-darwin-arm64.tar.gz
  tar -xzf /tmp/node-v24.19.0-darwin-arm64.tar.gz -C runtime
  rm -f /tmp/node-v24.19.0-darwin-arm64.tar.gz
fi
echo "  Node: $("$NODE_BIN" --version)"
echo "[2/3] installing npm dependencies (playwright + chromium)..."
export PATH="$SCRIPT_DIR/runtime/node-v24.19.0-darwin-arm64/bin:$PATH"
"$NODE_BIN" "$SCRIPT_DIR/runtime/node-v24.19.0-darwin-arm64/bin/npm" install --no-fund --no-audit
echo "[3/3] downloading Chromium for Playwright..."
"$NODE_BIN" "$SCRIPT_DIR/runtime/node-v24.19.0-darwin-arm64/bin/npx" playwright install chromium
echo "done. Try: ./deepseek-sync login"