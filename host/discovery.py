# -*- coding: utf-8 -*-
"""UDP 广播发现：手机发 TIMESCAM/DISCOVER，电脑回一条 HOST。"""

from __future__ import annotations

import json
import socket
import threading

from config import APP_TAG, DISCOVERY_PORT, PROTO_VER
from state import HostState


def discovery_loop(state: HostState, stop: threading.Event) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("0.0.0.0", DISCOVERY_PORT))
    except OSError as exc:
        state.events.put((
            "log",
            {"text": f"发现端口 {DISCOVERY_PORT} 打不开：{exc}（可在 App 里手动填 IP）"},
        ))
        sock.close()
        return

    sock.settimeout(1.0)
    host_name = socket.gethostname()
    while not stop.is_set():
        try:
            data, addr = sock.recvfrom(2048)
        except socket.timeout:
            continue
        except OSError:
            break

        text = data.decode("utf-8", "ignore").strip()
        if not (text.startswith(APP_TAG + "/DISCOVER") or text.startswith(APP_TAG + "/PING")):
            continue

        snap = state.snapshot()
        reply = {
            "name": host_name,
            "id": snap["id"],
            "hue": snap["hue"],
            "port": state.port,
            "dir": snap["dir"],
            "count": snap["count"],
            "ver": PROTO_VER,
        }
        payload = (APP_TAG + "/HOST " + json.dumps(reply, ensure_ascii=True)).encode("utf-8")
        try:
            sock.sendto(payload, addr)
        except OSError:
            pass
    sock.close()
