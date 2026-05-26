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
from http.server import BaseHTTPRequestHandler, HTTPServer

SAMPLE_PATH = "/srv/sample.mp4"
PORT = 8080


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

    def send_json(self, code, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, '{"status":"ok"}')
            return

        if re.match(r"^/recordings/[^/]+$", self.path):
            self._serve_recording()
            return

        self.send_json(404, '{"error":"not found"}')

    def _serve_recording(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer ") or len(auth) <= len("Bearer "):
            self.send_json(401, '{"error":"unauthorized"}')
            return

        size = os.path.getsize(SAMPLE_PATH)
        range_header = self.headers.get("Range")

        if range_header:
            self._serve_range(size, range_header)
        else:
            self._serve_full(size)

    def _serve_full(self, size):
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self._stream_bytes(0, size)

    def _serve_range(self, size, range_header):
        # Parse "bytes=N-M" or "bytes=N-"
        m = re.match(r"bytes=(\d+)-(\d*)", range_header)
        if not m:
            self.send_response(416)
            self.end_headers()
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

    def _stream_bytes(self, offset, length):
        chunk = 65536
        with open(SAMPLE_PATH, "rb") as f:
            f.seek(offset)
            remaining = length
            while remaining > 0:
                data = f.read(min(chunk, remaining))
                if not data:
                    break
                self.wfile.write(data)
                remaining -= len(data)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Download server listening on :{PORT}", flush=True)
    server.serve_forever()
