#!/usr/bin/env python3
"""
HTTP download server for mock-camera-wifi.

Endpoints:
  GET /health              -> 200 {"status":"ok"}   (no auth)
  GET /recordings/{id}     -> 200 MP4 or 206 Partial Content (Bearer required)
  Everything else          -> 404
"""

import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

SAMPLE_PATH = "/srv/sample.mp4"
PORT = 8080
# Any non-empty Bearer token is accepted by default. Set DOWNLOAD_TOKEN in the
# environment (or docker-compose.yml) to validate a specific value — useful for
# confirming the Flutter app sends the expected token.
DOWNLOAD_TOKEN = os.environ.get("DOWNLOAD_TOKEN", "")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:
        print(fmt % args, flush=True)

    def send_json(self, code: int, body: str) -> None:
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, '{"status":"ok"}')
            return

        if re.match(r"^/recordings/[^/]+$", path):
            self._serve_recording()
            return

        self.send_json(404, '{"error":"not found"}')

    def _serve_recording(self) -> None:
        auth = self.headers.get("Authorization", "")
        token = auth[len("Bearer "):] if auth.startswith("Bearer ") else ""
        if not token or (DOWNLOAD_TOKEN and token != DOWNLOAD_TOKEN):
            self.send_json(401, '{"error":"unauthorized"}')
            return

        if not os.path.exists(SAMPLE_PATH):
            self.send_json(503, '{"error":"media unavailable"}')
            return

        size = os.path.getsize(SAMPLE_PATH)
        range_header = self.headers.get("Range")

        if range_header:
            self._serve_range(size, range_header)
        else:
            self._serve_full(size)

    def _serve_full(self, size: int) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self._stream_bytes(0, size)

    def _serve_range(self, size: int, range_header: str) -> None:
        # Parse "bytes=N-M" or "bytes=N-" (open-ended).
        # Unsupported forms (e.g. suffix-range bytes=-N) fall back to a full
        # 200 response per RFC 9110 §14.2: a server that cannot satisfy the
        # range SHOULD send the full entity rather than 416.
        m = re.match(r"bytes=(\d+)-(\d*)", range_header)
        if not m:
            self._serve_full(size)
            return

        start = int(m.group(1))
        end = int(m.group(2)) if m.group(2) else size - 1
        end = min(end, size - 1)

        if start > end or start >= size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return

        length = end - start + 1
        self.send_response(206)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self._stream_bytes(start, length)

    def _stream_bytes(self, offset: int, length: int) -> None:
        chunk = 65536
        try:
            with open(SAMPLE_PATH, "rb") as f:
                f.seek(offset)
                remaining = length
                while remaining > 0:
                    data = f.read(min(chunk, remaining))
                    if not data:
                        break
                    self.wfile.write(data)
                    remaining -= len(data)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Download server listening on :{PORT}", flush=True)
    server.serve_forever()
