#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TimesCam Host —— 手机拍照，电脑秒收。

手机端和电脑连同一个 WiFi 即可：手机自动发现电脑（UDP 广播），
拍完直接把 JPEG 传到电脑选中的文件夹里。

用法：
    python main.py               启动图形界面
    python main.py --no-gui      只启动服务（看日志）
    python main.py --selftest    自检：起服务 → 模拟上传 → 打印结果
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

from config import (
    APP_NAME,
    APP_VER,
    DISCOVERY_PORT,
    HTTP_PORT,
    PROTO_VER,
    default_dir,
    human_size,
    load_config,
    local_ip,
)
from discovery import discovery_loop
from server import start_http
from state import HostState


def run_headless(state: HostState, port: int) -> None:
    server = start_http(state, port)
    if server is None:
        print(f"[x] 端口 {port}~{port + 20} 都被占用了")
        return

    threading.Thread(target=discovery_loop, args=(state, threading.Event()), daemon=True).start()
    print(f"[+] {APP_NAME} v{APP_VER}")
    print(f"[+] 保存目录：{state.get_dir()}")
    print(f"[+] 地址：{local_ip()}:{state.port}/upload")
    print(f"[+] 发现端口：{DISCOVERY_PORT}")
    print("[+] Ctrl+C 结束")

    try:
        while True:
            time.sleep(0.4)
            while not state.events.empty():
                kind, payload = state.events.get()
                if kind == "photo":
                    print(f"[+] {payload['name']}  {human_size(payload['size'])}  "
                          f"{payload['ms']:.0f} ms  {payload['speed']:.1f} MB/s")
                elif kind == "log":
                    print("[!]", payload.get("text", ""))
    except KeyboardInterrupt:
        print("\n[+] 已停止")
    finally:
        server.shutdown()


def run_selftest(state: HostState, port: int) -> int:
    server = start_http(state, port)
    if server is None:
        print("FAIL: http server")
        return 1
    actual = state.port

    stop = threading.Event()
    threading.Thread(target=discovery_loop, args=(state, stop), daemon=True).start()
    time.sleep(0.4)

    passed = 0
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{actual}/ping", timeout=5) as resp:
            ping = json.loads(resp.read().decode())
        print("ping:", ping)
        passed += 1 if ping.get("ok") else 0

        payload = b"\xff\xd8\xff\xe0" + os.urandom(180_000) + b"\xff\xd9"
        req = urllib.request.Request(
            f"http://127.0.0.1:{actual}/upload",
            data=payload,
            method="POST",
            headers={
                "Content-Type": "image/jpeg",
                "X-File-Name": urllib.parse.quote("TimesCam_selftest_001.jpg"),
                "X-Device": urllib.parse.quote("自检手机"),
            },
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            res = json.loads(resp.read().decode())
        print("upload:", res)
        passed += 1 if res.get("ok") else 0

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(3)
        sock.sendto(b"TIMESCAM/DISCOVER v1", ("127.0.0.1", DISCOVERY_PORT))
        data, _ = sock.recvfrom(2048)
        sock.close()
        print("discover:", data.decode("utf-8", "replace"))
        passed += 1 if data.startswith(b"TIMESCAM/HOST") else 0
    except Exception as exc:  # noqa: BLE001
        print("FAIL:", type(exc).__name__, exc)
    finally:
        stop.set()
        server.shutdown()

    print(f"selftest {passed}/3 passed")
    return 0 if passed == 3 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=f"{APP_NAME} · 同网快传相机上位机")
    parser.add_argument("--no-gui", action="store_true", help="不启动图形界面")
    parser.add_argument("--selftest", action="store_true", help="自检后退出")
    parser.add_argument("--port", type=int, default=0, help=f"直传端口（默认 {HTTP_PORT}）")
    parser.add_argument("--dir", default="", help="照片保存目录")
    args = parser.parse_args()

    cfg = load_config()
    port = args.port or int(cfg.get("port") or HTTP_PORT)
    save_dir = Path(args.dir or cfg.get("dir") or default_dir())

    if args.selftest and not args.dir:
        save_dir = Path(tempfile.mkdtemp(prefix="timescam_selftest_"))

    state = HostState(save_dir)
    state.port = port

    if args.selftest:
        return run_selftest(state, port)
    if args.no_gui:
        run_headless(state, port)
        return 0

    try:
        from ui import HostApp
    except Exception as exc:  # noqa: BLE001
        print(f"图形界面不可用：{exc}")
        print("可以改用：python main.py --no-gui")
        return 1

    try:
        app = HostApp(state, port)
    except Exception as exc:  # noqa: BLE001
        print(f"界面启动失败：{exc}")
        print("可以改用：python main.py --no-gui")
        return 1
    app.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
