# -*- coding: utf-8 -*-
"""运行期状态：保存目录、收到的照片、统计与事件队列。"""

from __future__ import annotations

import queue
import threading
import time
from pathlib import Path

from config import HTTP_PORT


class HostState:
    def __init__(self, save_dir: Path):
        self._lock = threading.Lock()
        self._dir = Path(save_dir)
        self._ensure_dir()
        self.port = HTTP_PORT
        self.events: "queue.Queue[tuple[str, dict]]" = queue.Queue()
        self.items: list[dict] = []
        self.count = 0
        self.total = 0
        self.last_ms = 0.0
        self.last_speed = 0.0
        self.last_seen = 0.0
        self.device = ""
        self.client_ip = ""

    def _ensure_dir(self) -> None:
        try:
            self._dir.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass

    def get_dir(self) -> Path:
        with self._lock:
            return self._dir

    def set_dir(self, path: str | Path) -> None:
        with self._lock:
            self._dir = Path(path)
        self._ensure_dir()
        self.events.put(("dir", {"dir": str(path)}))

    def touch(self, ip: str, device: str = "") -> None:
        with self._lock:
            self.last_seen = time.time()
            if ip:
                self.client_ip = ip
            if device:
                self.device = device

    def note(self, item: dict) -> None:
        with self._lock:
            self.items.insert(0, item)
            if len(self.items) > 400:
                self.items.pop()
            self.count += 1
            self.total += int(item.get("size", 0))
            self.last_ms = float(item.get("ms", 0.0))
            self.last_speed = float(item.get("speed", 0.0))
            self.last_seen = time.time()
            if item.get("device"):
                self.device = item["device"]
            if item.get("ip"):
                self.client_ip = item["ip"]
        self.events.put(("photo", item))

    def snapshot(self) -> dict:
        with self._lock:
            return {
                "count": self.count,
                "total": self.total,
                "last_ms": self.last_ms,
                "last_speed": self.last_speed,
                "last_seen": self.last_seen,
                "device": self.device,
                "client_ip": self.client_ip,
                "dir": str(self._dir),
                "items": list(self.items),
            }
