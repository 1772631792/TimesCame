# -*- coding: utf-8 -*-
"""HTTP 直传服务：/ping /info /upload。"""

from __future__ import annotations

import json
import os
import re
import socket
import threading
import time
import urllib.parse
import uuid
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from config import APP_VER, PORT_SPAN, PROTO_VER
from state import HostState

ALLOWED_EXT = (".jpg", ".jpeg", ".png", ".webp", ".heic")


def safe_name(raw: str) -> str:
    base = os.path.basename((raw or "").replace("\\", "/")).strip()
    base = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", base)
    ext = os.path.splitext(base)[1].lower()
    if ext not in ALLOWED_EXT:
        ext = ".jpg"
    stem = os.path.splitext(base)[0].strip(". ")
    if not stem:
        stem = "TimesCam_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:-3]
    return stem[:80] + ext


def unique_path(folder: Path, name: str) -> Path:
    target = folder / name
    if not target.exists():
        return target
    stem, ext = os.path.splitext(name)
    for i in range(1, 1000):
        cand = folder / f"{stem}_{i}{ext}"
        if not cand.exists():
            return cand
    return folder / f"{stem}_{uuid.uuid4().hex[:6]}{ext}"


def make_handler(state: HostState, port: int):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = f"TimesCamHost/{APP_VER}"

        def log_message(self, fmt, *args):
            pass

        # ---------- 基础响应
        def _json(self, code: int, payload: dict) -> None:
            body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
            try:
                self.send_response(code)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def _client_ip(self) -> str:
            return self.client_address[0] if self.client_address else ""

        # ---------- GET
        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            if path == "/ping":
                ip = self._client_ip()
                state.touch(ip)
                state.note_device(ip)
                self._json(200, {"ok": True, "name": socket.gethostname(), "t": time.time()})
            elif path == "/info":
                ip = self._client_ip()
                state.touch(ip)
                state.note_device(ip)
                snap = state.snapshot()
                self._json(200, {
                    "ok": True,
                    "name": socket.gethostname(),
                    "id": snap["id"],
                    "hue": snap["hue"],
                    "port": port,
                    "dir": snap["dir"],
                    "count": snap["count"],
                    "ver": PROTO_VER,
                    "app": APP_VER,
                })
            else:
                self.close_connection = True
                self._json(404, {"ok": False, "error": "not found"})

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Headers", "*")
            self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
            self.send_header("Content-Length", "0")
            self.end_headers()

        # ---------- POST
        def do_POST(self):
            if urllib.parse.urlparse(self.path).path != "/upload":
                self.close_connection = True
                self._json(404, {"ok": False, "error": "not found"})
                return
            self._upload()

        def _upload(self):
            ip = self._client_ip()
            try:
                length = int(self.headers.get("Content-Length", "0") or 0)
            except ValueError:
                length = 0
            if length <= 0:
                self.close_connection = True
                self._json(400, {"ok": False, "error": "empty body"})
                return

            raw_name = urllib.parse.unquote(self.headers.get("X-File-Name", "") or "")
            device = urllib.parse.unquote(self.headers.get("X-Device", "") or "")
            name = safe_name(raw_name)

            folder = state.get_dir()
            try:
                folder.mkdir(parents=True, exist_ok=True)
                target = unique_path(folder, name)
                tmp = folder / f".timescam_{uuid.uuid4().hex}.part"

                remaining = length
                t0 = time.perf_counter()
                with open(tmp, "wb") as fp:
                    while remaining > 0:
                        chunk = self.rfile.read(min(262144, remaining))
                        if not chunk:
                            break
                        fp.write(chunk)
                        remaining -= len(chunk)
                elapsed_ms = (time.perf_counter() - t0) * 1000.0

                if remaining > 0:
                    tmp.unlink(missing_ok=True)
                    self.close_connection = True
                    self._json(400, {"ok": False, "error": "connection closed early"})
                    return

                os.replace(tmp, target)
            except Exception as exc:  # noqa: BLE001
                self.close_connection = True
                self._json(500, {"ok": False, "error": f"{type(exc).__name__}: {exc}"})
                return

            speed = (length / 1024 / 1024) / (elapsed_ms / 1000.0) if elapsed_ms > 0 else 0.0
            state.note_device(ip, device, length)
            state.note({
                "path": str(target),
                "name": target.name,
                "size": length,
                "ms": elapsed_ms,
                "speed": speed,
                "at": time.time(),
                "device": device,
                "ip": ip,
            })

            self._json(200, {
                "ok": True,
                "file": target.name,
                "bytes": length,
                "ms": round(elapsed_ms, 1),
                "speed": round(speed, 2),
                "count": state.snapshot()["count"],
            })

    return Handler


def start_http(state: HostState, port: int) -> ThreadingHTTPServer | None:
    for candidate in range(port, port + PORT_SPAN):
        try:
            server = ThreadingHTTPServer(("0.0.0.0", candidate), make_handler(state, candidate))
        except OSError:
            continue
        server.daemon_threads = True
        state.port = candidate
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server
    return None
