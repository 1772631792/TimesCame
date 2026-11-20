# -*- coding: utf-8 -*-
"""运行期状态：保存目录、收到的照片、统计与事件队列。"""

from __future__ import annotations

import queue
import threading
import time
from pathlib import Path

from config import HTTP_PORT, hue_from_id

ONLINE_WINDOW = 120.0


class HostState:
    def __init__(self, save_dir: Path, host_id: str = "timescam", hue: int | None = None):
        self._lock = threading.Lock()
        self._dir = Path(save_dir)
        self._ensure_dir()
        self.port = HTTP_PORT
        self.host_id = host_id
        self.hue = hue_from_id(host_id) if hue is None else hue
        self.events: "queue.Queue[tuple[str, dict]]" = queue.Queue()
        self.items: list[dict] = []
        self.devices: dict[str, dict] = {}
        self.focus_ip = ""
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

    def note_device(self, ip: str, name: str = "", size: int = 0) -> None:
        """记下这台手机：头像、张数、最后活跃时间。"""
        if not ip:
            return
        with self._lock:
            info = self.devices.setdefault(
                ip, {"ip": ip, "name": "手机", "count": 0, "bytes": 0, "last_seen": 0.0})
            if name:
                info["name"] = name
            if size:
                info["count"] += 1
                info["bytes"] += size
            info["last_seen"] = time.time()
            if len(self.devices) > 20:
                oldest = min(self.devices.values(), key=lambda d: d["last_seen"])
                self.devices.pop(oldest["ip"], None)
            self.last_seen = time.time()
            self.client_ip = ip
            if name:
                self.device = name

    def devices_online(self) -> list[dict]:
        now = time.time()
        with self._lock:
            alive = [dict(d) for d in self.devices.values() if now - d["last_seen"] < ONLINE_WINDOW]
        alive.sort(key=lambda d: (-d["count"], d["name"]))
        return alive

    def set_focus(self, ip: str) -> None:
        with self._lock:
            self.focus_ip = ip if self.focus_ip != ip else ""
        self.events.put(("focus", {"ip": self.focus_ip}))

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
        now = time.time()
        with self._lock:
            devices = [dict(d) for d in self.devices.values() if now - d["last_seen"] < ONLINE_WINDOW]
            return {
                "id": self.host_id,
                "hue": self.hue,
                "count": self.count,
                "total": self.total,
                "last_ms": self.last_ms,
                "last_speed": self.last_speed,
                "last_seen": self.last_seen,
                "device": self.device,
                "client_ip": self.client_ip,
                "focus": self.focus_ip,
                "devices": sorted(devices, key=lambda d: (-d["count"], d["name"])),
                "dir": str(self._dir),
                "items": list(self.items),
            }
