#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 release/ 里的产物发到 GitHub Release。

用法：
    set GITHUB_TOKEN=ghp_xxx          # Windows
    export GITHUB_TOKEN=ghp_xxx       # macOS / Linux
    python tools/publish_release.py

    python tools/publish_release.py --dry-run      # 只打印，不发请求
    python tools/publish_release.py --version 1.1.0 --repo owner/name

需要 token 具备 repo 权限（fine-grained token 勾选 Contents: Read and write）。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://api.github.com"
UPLOAD = "https://uploads.github.com"


def repo_from_git() -> str:
    try:
        url = subprocess.check_output(
            ["git", "remote", "get-url", "origin"], cwd=ROOT, text=True).strip()
    except Exception:
        return ""
    if url.startswith("git@github.com:"):
        url = url.split(":", 1)[1]
    url = url.split("github.com/")[-1]
    return url[:-4] if url.endswith(".git") else url


def token_from_git() -> str:
    """环境变量没有 token 时，退而问本机的 git 凭据（GCM / store 都支持）。"""
    try:
        out = subprocess.run(
            ["git", "credential", "fill"],
            input="protocol=https\nhost=github.com\n\n",
            capture_output=True, text=True, cwd=ROOT, timeout=20,
        )
        for line in out.stdout.splitlines():
            if line.startswith("password="):
                return line[9:].strip()
    except Exception:
        pass
    return ""


def version_from_pubspec() -> str:
    for line in (ROOT / "app" / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+")[0]
    return "0.0.0"


def request(url: str, token: str, method: str = "GET", data: bytes | None = None,
            content_type: str = "application/json") -> dict:
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", content_type)
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "TimesCam-release-bot")
    with urllib.request.urlopen(req, timeout=600) as resp:
        body = resp.read().decode("utf-8", "replace")
    return json.loads(body) if body.strip() else {}


def main() -> int:
    parser = argparse.ArgumentParser(description="发布 TimesCam 到 GitHub Release")
    parser.add_argument("--version", default="", help="默认读 app/pubspec.yaml")
    parser.add_argument("--repo", default="", help="owner/name，默认读 git remote")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN", ""))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--draft", action="store_true", help="发成草稿")
    args = parser.parse_args()

    version = args.version or version_from_pubspec()
    repo = args.repo or repo_from_git()
    token = args.token or token_from_git()
    tag = f"v{version}"
    bundle = ROOT / "release" / f"TimesCam-v{version}"
    notes_file = ROOT / "docs" / "release-notes" / f"v{version}.md"

    if not repo:
        print("[x] 找不到仓库，用 --repo owner/name 指定")
        return 1
    if not bundle.exists():
        print(f"[x] 没找到发布目录：{bundle}")
        print("    先把 exe / apk 复制进去（参考 README「发布」一节）")
        return 1

    assets = sorted(p for p in bundle.iterdir() if p.suffix.lower() in (".exe", ".apk", ".zip"))
    if not assets:
        print(f"[x] {bundle} 里没有可上传的文件")
        return 1

    body = notes_file.read_text(encoding="utf-8") if notes_file.exists() else f"TimesCam {tag}"
    print(f"[*] 仓库：{repo}")
    print(f"[*] 标签：{tag}")
    print(f"[*] 资产：{', '.join(a.name for a in assets)}")

    if args.dry_run:
        print("[dry-run] 以上信息无误，去掉 --dry-run 就会真的发")
        return 0

    if not token:
        print("[x] 没找到 token：环境变量 GITHUB_TOKEN 为空，git 凭据里也没有。")
        print("    生成一个有 repo 权限的 token 后：")
        print("    set GITHUB_TOKEN=ghp_xxx")
        return 1

    payload = json.dumps({
        "tag_name": tag,
        "name": f"TimesCam {tag}",
        "body": body,
        "draft": args.draft,
        "prerelease": False,
    }).encode("utf-8")

    try:
        release = request(f"{API}/repos/{repo}/releases", token, "POST", payload)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        print(f"[x] 创建 Release 失败：{exc.code} {detail[:300]}")
        return 1

    release_id = release.get("id")
    upload_url = release.get("upload_url", "").split("{")[0]
    print(f"[+] Release 已创建：{release.get('html_url', '')}")

    for asset in assets:
        url = f"{upload_url}?name={urllib.parse.quote(asset.name)}"
        try:
            request(url, token, "POST", asset.read_bytes(), "application/octet-stream")
            print(f"[+] 已上传 {asset.name}（{asset.stat().st_size / 1024 / 1024:.1f} MB）")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            print(f"[x] 上传 {asset.name} 失败：{exc.code} {detail[:200]}")
            return 1

    print(f"[ok] 完成：{release.get('html_url', '')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
