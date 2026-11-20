# -*- coding: utf-8 -*-
"""常量、本地配置与几个小工具。"""

from __future__ import annotations

import json
import socket
import uuid
from pathlib import Path

APP_NAME = "TimesCam Host"
APP_VER = "1.1.0"

DISCOVERY_PORT = 37020
HTTP_PORT = 37021
PORT_SPAN = 20
APP_TAG = "TIMESCAM"
PROTO_VER = 1

CONFIG_PATH = Path.home() / ".timescam_host.json"


def default_dir() -> Path:
    home = Path.home()
    pics = home / "Pictures"
    base = pics if pics.exists() else home
    return base / "TimesCam"


def load_config() -> dict:
    """dir / port / id；id 是这台电脑的身份，手机靠它认出「上次那台」。"""
    cfg = {"dir": str(default_dir()), "port": HTTP_PORT, "id": uuid.uuid4().hex[:8]}
    try:
        if CONFIG_PATH.exists():
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                cfg.update({k: v for k, v in data.items() if k in cfg})
    except Exception:
        pass
    return cfg


def save_config(cfg: dict) -> None:
    try:
        current = load_config()
        current.update(cfg)
        CONFIG_PATH.write_text(json.dumps(current, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass


def update_config(**changes) -> dict:
    cfg = load_config()
    cfg.update(changes)
    save_config(cfg)
    return cfg


def hue_from_id(value: str) -> int:
    """同一个 id 永远得到同一个色相，头像颜色就稳定了。"""
    total = sum(ord(ch) * (i + 7) for i, ch in enumerate(value or "timescam"))
    return total % 360


def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def human_size(n: float) -> str:
    n = float(n)
    if n >= 1024 * 1024 * 1024:
        return f"{n / 1024 / 1024 / 1024:.2f} GB"
    if n >= 1024 * 1024:
        return f"{n / 1024 / 1024:.1f} MB"
    if n >= 1024:
        return f"{n / 1024:.0f} KB"
    return f"{n:.0f} B"


def short_path(path: str, limit: int = 44) -> str:
    return path if len(path) <= limit else path[:20] + " … " + path[-20:]
