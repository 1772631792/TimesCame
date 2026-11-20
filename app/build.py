#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TimesCam 手机端一键打包。

做的事情：
  1. 用 tools/make_icon.py 现画二次元图标，写进 Android 五档 mipmap
  2. 把代理写进 android/gradle.properties（默认 127.0.0.1:7897，Gradle 下载飞快）
  3. flutter build apk --release
  4. 复制到 app/dist/TimesCam-v{版本}-{日期}.apk

用法：
    cd app
    python build.py
    python build.py --proxy ""          # 不用代理
    python build.py --no-icon           # 不重画图标
    python build.py --no-build          # 只生成图标 + 写代理，不编译
    python build.py --split-abi         # 分 ABI 出包，体积更小
"""

from __future__ import annotations

import argparse
import os
import shutil
import socket
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
ROOT = APP_DIR.parent
TOOLS = ROOT / "tools"
RES_DIR = APP_DIR / "android" / "app" / "src" / "main" / "res"
GRADLE_PROPS = APP_DIR / "android" / "gradle.properties"
DIST = APP_DIR / "dist"
APP_NAME = "TimesCam"
DEFAULT_PROXY = "127.0.0.1:7897"


def read_version() -> str:
    for line in (APP_DIR / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+")[0]
    return "0.0.0"


def make_icons() -> bool:
    try:
        sys.path.insert(0, str(TOOLS))
        from make_icon import build_android_icons, build_png, render
    except Exception as exc:  # noqa: BLE001
        print(f"[icon] 跳过：{exc}（需要 pip install Pillow）")
        return False

    master = render(2048)
    files = build_android_icons(RES_DIR, master)
    build_png(TOOLS / "icon_preview.png", master, 512)
    print(f"[icon] 已写入 {len(files)} 档 mipmap（mdpi~xxxhdpi）")
    return True


def proxy_alive(proxy: str) -> bool:
    host, _, port = proxy.partition(":")
    if not host:
        return True
    try:
        with socket.create_connection((host, int(port or 7897)), timeout=1.2):
            return True
    except (OSError, ValueError):
        return False


def apply_proxy(proxy: str) -> None:
    """写 systemProp 给 Gradle，同时设置环境变量给 pub / wrapper 用。"""
    existing = []
    if GRADLE_PROPS.exists():
        existing = GRADLE_PROPS.read_text(encoding="utf-8").splitlines()

    kept = [ln for ln in existing if not ln.strip().startswith("systemProp.") or "proxy" not in ln]
    if proxy:
        host, _, port = proxy.partition(":")
        port = port or "7897"
        kept += [
            "",
            "# added by app/build.py: route Gradle through local proxy",
            f"systemProp.http.proxyHost={host}",
            f"systemProp.http.proxyPort={port}",
            f"systemProp.https.proxyHost={host}",
            f"systemProp.https.proxyPort={port}",
            "systemProp.http.nonProxyHosts=localhost|127.0.0.1|10.*|192.168.*",
            "systemProp.https.nonProxyHosts=localhost|127.0.0.1|10.*|192.168.*",
        ]
        print(f"[proxy] Gradle 走代理 {host}:{port}")
    else:
        print("[proxy] 已清掉 Gradle 代理配置")

    GRADLE_PROPS.parent.mkdir(parents=True, exist_ok=True)
    GRADLE_PROPS.write_text("\n".join(kept).rstrip() + "\n", encoding="utf-8")


def build_env(proxy: str) -> dict:
    env = os.environ.copy()
    if proxy:
        url = proxy if "://" in proxy else f"http://{proxy}"
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
            env[key] = url
        host, _, port = proxy.partition(":")
        port = port or "7897"
        env["GRADLE_OPTS"] = (
            f"-Dhttp.proxyHost={host} -Dhttp.proxyPort={port} "
            f"-Dhttps.proxyHost={host} -Dhttps.proxyPort={port}"
        )
    return env


def run_build(proxy: str, split_abi: bool) -> int:
    args = ["build", "apk", "--release"]
    if split_abi:
        args.append("--split-per-abi")

    # Windows 上 flutter 是 .bat，必须借 cmd 才能被 subprocess 拉起
    flutter = os.environ.get("FLUTTER", "")
    if sys.platform == "win32":
        cmd = ["cmd", "/c", flutter or "flutter", *args]
    else:
        cmd = [flutter or "flutter", *args]

    print("[build] flutter " + " ".join(args))
    started = time.time()
    try:
        result = subprocess.run(cmd, cwd=APP_DIR, env=build_env(proxy))
    except FileNotFoundError:
        print("[x] 找不到 flutter，请把 Flutter 的 bin 目录加入 PATH（或设 FLUTTER 环境变量）")
        return 1
    used = time.time() - started
    print(f"[build] 用时 {used / 60:.1f} 分钟")
    if used > 420:
        print("[tip] 首次 Release 构建要下 Gradle 依赖、编译原生库，慢是正常的；"
              "之后再打只需要 1~2 分钟")
    return result.returncode


def collect_outputs(version: str, split_abi: bool) -> list[Path]:
    src = APP_DIR / "build" / "app" / "outputs" / "flutter-apk"
    DIST.mkdir(exist_ok=True)
    copied = []
    if split_abi:
        apks = sorted(src.glob("app-*-release.apk"))
    else:
        apks = [src / "app-release.apk"] if (src / "app-release.apk").exists() else []
    for apk in apks:
        suffix = ""
        if split_abi:
            suffix = "-" + apk.name.replace("app-", "").replace("-release.apk", "")
        target = DIST / f"{APP_NAME}-v{version}-{date.today():%Y%m%d}{suffix}.apk"
        shutil.copy2(apk, target)
        copied.append(target)
    return copied


def main() -> int:
    parser = argparse.ArgumentParser(description="打包 TimesCam 手机端 APK")
    parser.add_argument("--proxy", default=DEFAULT_PROXY,
                        help=f"Gradle 代理，默认 {DEFAULT_PROXY}，填空字符串关闭")
    parser.add_argument("--no-icon", action="store_true", help="不重新生成启动图标")
    parser.add_argument("--no-build", action="store_true", help="只生成图标/写代理，不编译")
    parser.add_argument("--split-abi", action="store_true", help="按 ABI 分包")
    args = parser.parse_args()

    print("=" * 52)
    print(" TimesCam · 打包")
    print("=" * 52)

    if args.proxy and not proxy_alive(args.proxy):
        print(f"[proxy] {args.proxy} 连不上，这次先不走代理（检查 Clash / v2ray 是否在跑）")
        args.proxy = ""

    version = read_version()
    if not args.no_icon:
        make_icons()
    apply_proxy(args.proxy)

    if args.no_build:
        print("[build] --no-build，跳过编译")
        return 0

    code = run_build(args.proxy, args.split_abi)
    if code != 0:
        print(f"[x] 编译失败，退出码 {code}")
        return code

    files = collect_outputs(version, args.split_abi)
    if not files:
        print("[x] 没找到 APK 产物")
        return 1

    for f in files:
        print(f"[ok] {f}  ({f.stat().st_size / 1024 / 1024:.1f} MB)")

    try:
        if sys.platform == "win32":
            subprocess.run(["explorer", str(DIST)])
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
