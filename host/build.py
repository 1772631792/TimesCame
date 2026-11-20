#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把上位机打包成单个 exe（PyInstaller），图标由 tools/make_icon.py 现画。

用法：
    cd host
    python build.py                   # 默认走系统代理 127.0.0.1:7897 装 PyInstaller
    python build.py --no-icon         # 跳过图标
    python build.py --proxy ""        # 不用代理
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

HOST_DIR = Path(__file__).resolve().parent
ROOT = HOST_DIR.parent
TOOLS = ROOT / "tools"
DIST = HOST_DIR / "dist"
BUILD = HOST_DIR / "build"
EXE_NAME = "TimesCamHost"


def proxy_alive(proxy: str) -> bool:
    host, _, port = proxy.partition(":")
    if not host:
        return True
    try:
        with socket.create_connection((host, int(port or 7897)), timeout=1.2):
            return True
    except (OSError, ValueError):
        return False


def proxy_env(proxy: str) -> dict:
    env = os.environ.copy()
    if proxy:
        url = proxy if "://" in proxy else f"http://{proxy}"
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
            env[key] = url
    return env


def ensure_pillow(proxy: str) -> bool:
    if importlib.util.find_spec("PIL") is not None:
        return True
    print("[icon] 没装 Pillow，先装上（只用于生成图标）")
    cmd = [sys.executable, "-m", "pip", "install", "Pillow"]
    if proxy:
        cmd += ["--proxy", proxy]
    return subprocess.run(cmd, env=proxy_env(proxy)).returncode == 0


def make_icon(proxy: str) -> Path | None:
    if not ensure_pillow(proxy):
        print("[icon] Pillow 装不上，这次用默认图标")
        return None
    sys.path.insert(0, str(TOOLS))
    try:
        from make_icon import build_ico, build_png, render
    except Exception as exc:  # noqa: BLE001
        print(f"[icon] 图标脚本加载失败：{exc}")
        return None

    master = render(2048)
    ico = build_ico(HOST_DIR / "icon.ico", master)
    png = build_png(HOST_DIR / "icon.png", master, 512)
    print(f"[icon] {ico.name} / {png.name} 已生成（二次元大眼睛）")
    return ico


def ensure_pyinstaller(proxy: str) -> bool:
    if importlib.util.find_spec("PyInstaller") is not None:
        return True
    print("[exe] 没装 PyInstaller，正在安装 …")
    cmd = [sys.executable, "-m", "pip", "install", "pyinstaller"]
    if proxy:
        cmd += ["--proxy", proxy]
    ok = subprocess.run(cmd, env=proxy_env(proxy)).returncode == 0
    if not ok:
        print("[exe] 安装失败，请手动执行：pip install pyinstaller")
    return ok


def build_exe(icon: Path | None, proxy: str) -> int:
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm", "--clean",
        "--onefile", "--windowed",
        "--name", EXE_NAME,
        "--distpath", str(DIST),
        "--workpath", str(BUILD / "work"),
        "--specpath", str(BUILD),
    ]
    if icon is not None:
        cmd += ["--icon", str(icon), "--add-data", f"{icon}{os.pathsep}."]
    cmd.append(str(HOST_DIR / "main.py"))

    print("[exe] " + " ".join(str(c) for c in cmd[:8]) + " …")
    result = subprocess.run(cmd, cwd=HOST_DIR, env=proxy_env(proxy))
    if result.returncode != 0:
        print(f"[exe] 打包失败，退出码 {result.returncode}")
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="打包 TimesCam Host 单文件 exe")
    parser.add_argument("--proxy", default="127.0.0.1:7897",
                        help="pip 用的代理，默认 127.0.0.1:7897，填空字符串表示不用")
    parser.add_argument("--no-icon", action="store_true", help="不重新生成图标")
    parser.add_argument("--keep-build", action="store_true", help="保留中间产物")
    args = parser.parse_args()

    print("=" * 52)
    print(" TimesCam Host · 打包")
    print("=" * 52)

    if args.proxy and not proxy_alive(args.proxy):
        print(f"[proxy] {args.proxy} 连不上，改用直连（装包可能慢）")
        args.proxy = ""

    icon = None if args.no_icon else make_icon(args.proxy)
    if icon is None and not args.no_icon:
        fallback = HOST_DIR / "icon.ico"
        icon = fallback if fallback.exists() else None

    if not ensure_pyinstaller(args.proxy):
        return 1

    code = build_exe(icon, args.proxy)
    if code != 0:
        return code

    exe = DIST / f"{EXE_NAME}.exe"
    if not exe.exists():
        print(f"[exe] 没找到产物：{exe}")
        return 1

    size = exe.stat().st_size / 1024 / 1024
    print(f"[exe] 完成：{exe}  ({size:.1f} MB)")

    if not args.keep_build:
        shutil.rmtree(BUILD, ignore_errors=True)
        print("[exe] 已清理中间目录")

    try:
        if sys.platform == "win32":
            subprocess.run(["explorer", str(DIST)])
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
