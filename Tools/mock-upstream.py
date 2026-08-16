#!/usr/bin/env python3
# Dev-only mock DeepSeek upstream for Phase A gateway validation.
# Emulates POST /chat/completions (non-stream + stream) with usage objects.
# Never used by the app itself.
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 43210

USAGE = {
    "prompt_tokens": 12,
    "completion_tokens": 34,
    "total_tokens": 46,
    "prompt_cache_hit_tokens": 5,
    "prompt_cache_miss_tokens": 7,
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[mock-upstream] " + fmt % args + "\n")

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
        except Exception:
            payload = {}
        stream = bool(payload.get("stream", False))
        if stream:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            chunks = [
                {"choices": [{"delta": {"content": "Hello"}}]},
                {"choices": [{"delta": {"content": " world"}}]},
                {"choices": [{"delta": {}, "finish_reason": "stop"}], "usage": USAGE},
            ]
            for chunk in chunks:
                data = "data: " + json.dumps(chunk) + "\n\n"
                self.wfile.write(data.encode("utf-8"))
                self.wfile.flush()
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        else:
            resp = {
                "id": "mock-1",
                "object": "chat.completion",
                "model": payload.get("model", "deepseek-chat"),
                "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": "Hello from mock"}}],
                "usage": USAGE,
            }
            data = json.dumps(resp).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


print("mock upstream listening on 127.0.0.1:" + str(PORT), flush=True)
HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
