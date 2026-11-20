# -*- coding: utf-8 -*-
"""Tkinter 主界面。"""

from __future__ import annotations

import os
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path

from config import (
    APP_NAME,
    APP_VER,
    DISCOVERY_PORT,
    PROTO_VER,
    default_dir,
    human_size,
    hue_from_id,
    local_ip,
    short_path,
    update_config,
)
from discovery import discovery_loop
from draw import (
    GhostButton,
    GradientButton,
    PhotoGrid,
    blend,
    draw_gradient_round,
    hue_color,
    initial_of,
    mix_bg,
)
from server import start_http
from state import HostState
from theme import (
    ACCENT,
    ACCENT2,
    BG,
    CARD,
    CARD2,
    MUTED,
    OK,
    PANEL,
    STROKE,
    SUB,
    TEXT,
    WARN,
    pick_font,
)


def bundled_icon() -> Path | None:
    """PyInstaller 单文件运行时资源在 _MEIPASS 里。"""
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    for name in ("icon.ico", "app.ico"):
        candidate = base / name
        if candidate.exists():
            return candidate
    return None


class HostApp:
    def __init__(self, state: HostState, port: int):
        import tkinter as tk
        import tkinter.font as tkfont

        self.tk = tk
        self.state = state
        self.port = port
        self.stop = threading.Event()

        self.root = tk.Tk()
        self.root.title(APP_NAME)
        self.root.configure(bg=BG)
        self.root.geometry("1180x760")
        self.root.minsize(980, 640)
        self.font = pick_font(tkfont)

        icon = bundled_icon()
        if icon is not None:
            try:
                self.root.iconbitmap(default=str(icon))
            except Exception:
                pass

        self._last_status = None
        self._last_counts = None
        self._device_sig = None

        self._build()
        self._start_servers()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.after(80, self._dark_titlebar)
        self.root.after(120, self._poll)

    # ---------------------------------------------------------- 启动 / 关闭
    def _start_servers(self):
        self.server = start_http(self.state, self.port)
        if self.server is None:
            self.set_footer(f"HTTP 端口 {self.port} 打不开，防火墙或其他程序占用了它")
        self.port = self.state.port
        threading.Thread(target=discovery_loop, args=(self.state, self.stop), daemon=True).start()
        self.addr_label.configure(text=f"{local_ip()}:{self.port}")
        self.set_footer("已就绪，手机和电脑连同一个 WiFi 即可自动发现")

    def _dark_titlebar(self):
        if sys.platform != "win32":
            return
        try:
            import ctypes

            hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
            flag = ctypes.c_int(1)
            for attr in (20, 19):
                ctypes.windll.dwmapi.DwmSetWindowAttribute(
                    hwnd, attr, ctypes.byref(flag), ctypes.sizeof(flag))
        except Exception:
            pass

    def _on_close(self):
        self.stop.set()
        try:
            if getattr(self, "server", None):
                self.server.shutdown()
        except Exception:
            pass
        try:
            self.root.destroy()
        except Exception:
            pass

    # ---------------------------------------------------------- 界面
    def _build(self):
        tk = self.tk
        root = self.root
        root.grid_columnconfigure(0, weight=1)
        root.grid_rowconfigure(2, weight=1)

        strip = tk.Canvas(root, height=3, bg=BG, highlightthickness=0, bd=0)
        strip.grid(row=0, column=0, sticky="ew")
        strip.bind("<Configure>", lambda e: self._gradient_strip(strip, e.width))

        header = tk.Frame(root, bg=BG)
        header.grid(row=1, column=0, sticky="ew", padx=22, pady=(16, 12))
        header.grid_columnconfigure(2, weight=1)

        logo = tk.Canvas(header, width=46, height=46, bg=BG, highlightthickness=0, bd=0)
        logo.grid(row=0, column=0, rowspan=2, sticky="w")
        draw_gradient_round(logo, 46, 46, 14, ACCENT, ACCENT2)
        logo.create_oval(14, 18, 32, 36, fill="#FFFFFF", outline="")
        logo.create_oval(19, 23, 27, 31, fill=ACCENT, outline="")
        logo.create_rectangle(17, 13, 29, 18, fill="#FFFFFF", outline="")

        tk.Label(header, text="TimesCam", bg=BG, fg=TEXT,
                 font=(self.font, 19, "bold")).grid(row=0, column=1, sticky="sw", padx=(12, 0))
        tk.Label(header, text="手机拍照 · 电脑秒收", bg=BG, fg=SUB,
                 font=(self.font, 9)).grid(row=1, column=1, sticky="nw", padx=(12, 0))

        right = tk.Frame(header, bg=BG)
        right.grid(row=0, column=3, rowspan=2, sticky="e")
        self.status_label = tk.Label(right, text="● 等待手机连接", bg=BG, fg=WARN,
                                     font=(self.font, 10, "bold"))
        self.status_label.pack(anchor="e")
        self.addr_label = tk.Label(right, text="0.0.0.0:37021", bg=BG, fg=ACCENT,
                                   font=(self.font, 9), cursor="hand2")
        self.addr_label.pack(anchor="e", pady=(4, 0))
        self.addr_label.bind("<Button-1>", lambda e: self.copy_address())

        body = tk.Frame(root, bg=BG)
        body.grid(row=2, column=0, sticky="nsew", padx=22)
        body.grid_columnconfigure(1, weight=1)
        body.grid_rowconfigure(0, weight=1)

        left = tk.Frame(body, bg=BG)
        left.grid(row=0, column=0, sticky="nsw", padx=(0, 16))
        left.grid_columnconfigure(0, weight=1, minsize=300)

        self._build_folder_card(left)
        self._build_link_card(left)
        self._build_stats_card(left)

        right_panel = tk.Frame(body, bg=PANEL, highlightbackground=STROKE, highlightthickness=1)
        right_panel.grid(row=0, column=1, sticky="nsew")
        right_panel.grid_rowconfigure(1, weight=1)
        right_panel.grid_columnconfigure(0, weight=1)

        head = tk.Frame(right_panel, bg=PANEL)
        head.grid(row=0, column=0, sticky="ew", padx=14, pady=(12, 8))
        head.grid_columnconfigure(1, weight=1)
        tk.Label(head, text="已接收照片", bg=PANEL, fg=TEXT,
                 font=(self.font, 12, "bold")).grid(row=0, column=0, sticky="w")
        self.count_badge = tk.Label(head, text="0 张", bg=mix_bg(ACCENT, 0.18, PANEL),
                                    fg=ACCENT, font=(self.font, 9, "bold"), padx=8, pady=2)
        self.count_badge.grid(row=0, column=1, sticky="w", padx=(8, 0))
        GhostButton(head, "打开文件夹", command=self.open_folder, width=96, height=32,
                    bg=PANEL, fg=SUB, font=(self.font, 9)).grid(row=0, column=2, sticky="e")

        grid_holder = tk.Frame(right_panel, bg=PANEL)
        grid_holder.grid(row=1, column=0, sticky="nsew", padx=6, pady=(0, 6))
        self.grid_view = PhotoGrid(grid_holder, self.state, self.font, self.open_path)
        self.grid_view.refresh(force=True)

        footer = tk.Frame(root, bg=BG)
        footer.grid(row=3, column=0, sticky="ew", padx=22, pady=(10, 14))
        footer.grid_columnconfigure(0, weight=1)
        self.footer_label = tk.Label(footer, text="启动中…", bg=BG, fg=MUTED,
                                     font=(self.font, 9), anchor="w")
        self.footer_label.grid(row=0, column=0, sticky="w")
        tk.Label(footer, text=f"v{APP_VER} · 协议 v{PROTO_VER} · 端口 {DISCOVERY_PORT}/{self.port}",
                 bg=BG, fg=MUTED, font=(self.font, 9)).grid(row=0, column=1, sticky="e")

    def _gradient_strip(self, canvas, width):
        canvas.delete("all")
        steps = max(1, width // 6)
        for i in range(steps):
            x0 = i * width / steps
            x1 = (i + 1) * width / steps
            canvas.create_rectangle(x0, 0, x1 + 1, 3, fill=blend(ACCENT, ACCENT2, i / steps),
                                    outline="")

    def _card(self, parent, title: str):
        tk = self.tk
        outer = tk.Frame(parent, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        outer.pack(fill="x", pady=(0, 12))
        inner = tk.Frame(outer, bg=CARD, padx=14, pady=12)
        inner.pack(fill="both", expand=True)
        tk.Label(inner, text=title, bg=CARD, fg=MUTED,
                 font=(self.font, 8, "bold")).pack(anchor="w")
        return inner

    def _build_folder_card(self, parent):
        tk = self.tk
        inner = self._card(parent, "保存位置")

        self.dir_label = tk.Label(inner, text="", bg=CARD, fg=TEXT, font=(self.font, 10),
                                  wraplength=268, justify="left", anchor="w")
        self.dir_label.pack(anchor="w", pady=(7, 4))

        self.dir_hint = tk.Label(inner, text="每次拍摄会直接写进这个文件夹", bg=CARD, fg=MUTED,
                                 font=(self.font, 8), anchor="w")
        self.dir_hint.pack(anchor="w", pady=(0, 10))

        row = tk.Frame(inner, bg=CARD)
        row.pack(fill="x")
        GradientButton(row, "选择文件夹", command=self.pick_folder, width=124, height=34,
                       bg=CARD, font=(self.font, 9, "bold")).pack(side="left")
        GhostButton(row, "打开", command=self.open_folder, width=64, height=34,
                    bg=CARD, font=(self.font, 9)).pack(side="left", padx=(8, 0))

        self._refresh_dir_label()

    def _build_link_card(self, parent):
        tk = self.tk
        inner = self._card(parent, "连接")

        row = tk.Frame(inner, bg=CARD)
        row.pack(fill="x", pady=(7, 6))
        self.link_dot = tk.Canvas(row, width=9, height=9, bg=CARD, highlightthickness=0)
        self.link_dot.pack(side="left", pady=(2, 0))
        self.link_dot.create_oval(0, 0, 8, 8, fill=WARN, outline="")
        self.link_text = tk.Label(row, text="等待手机连接", bg=CARD, fg=TEXT,
                                  font=(self.font, 10, "bold"))
        self.link_text.pack(side="left", padx=(8, 0))

        self.link_sub = tk.Label(inner, text="发现端口 37020 · 直传端口 37021", bg=CARD,
                                 fg=SUB, font=(self.font, 8), anchor="w", justify="left",
                                 wraplength=268)
        self.link_sub.pack(anchor="w")

        self.device_box = tk.Frame(inner, bg=CARD)
        self.device_box.pack(fill="x")

        tk.Label(inner, text="手机端打开 TimesCam，同一个 WiFi 自动连",
                 bg=CARD, fg=MUTED, font=(self.font, 8), anchor="w",
                 justify="left", wraplength=268).pack(anchor="w", pady=(6, 0))

    def _build_stats_card(self, parent):
        tk = self.tk
        inner = self._card(parent, "本次统计")
        grid = tk.Frame(inner, bg=CARD)
        grid.pack(fill="x", pady=(9, 0))

        self.stat_values: dict[str, tk.Label] = {}
        cells = [("count", "已接收"), ("total", "总容量"), ("ms", "最近耗时"), ("speed", "最高速度")]
        for i, (key, label) in enumerate(cells):
            cell = tk.Frame(grid, bg=CARD2, highlightbackground=STROKE, highlightthickness=1)
            cell.grid(row=i // 2, column=i % 2, sticky="nsew", padx=(0, 6), pady=(0, 6))
            grid.grid_columnconfigure(i % 2, weight=1)
            value = tk.Label(cell, text="—", bg=CARD2, fg=TEXT, font=(self.font, 13, "bold"),
                             anchor="w")
            value.pack(fill="x", padx=10, pady=(9, 0))
            tk.Label(cell, text=label, bg=CARD2, fg=MUTED, font=(self.font, 8),
                     anchor="w").pack(fill="x", padx=10, pady=(1, 9))
            self.stat_values[key] = value

    # ---------------------------------------------------------- 动作
    def set_footer(self, text: str):
        try:
            self.footer_label.configure(text=text)
        except Exception:
            pass

    def _refresh_dir_label(self):
        path = str(self.state.snapshot()["dir"])
        self.dir_label.configure(text=short_path(path))
        try:
            is_default = Path(path).resolve() == default_dir().resolve()
        except OSError:
            is_default = False
        self.dir_hint.configure(
            text="每次拍摄会直接写进这个文件夹" if is_default else "自定义文件夹 · 可随时切换")

    def pick_folder(self):
        from tkinter import filedialog

        chosen = filedialog.askdirectory(initialdir=str(self.state.get_dir()),
                                         title="选择照片保存文件夹")
        if chosen:
            self.state.set_dir(chosen)
            self._refresh_dir_label()
            update_config(dir=chosen)
            self.set_footer(f"保存位置已切换：{chosen}")

    def open_folder(self):
        self.open_path(str(self.state.get_dir()))

    def open_path(self, path: str):
        try:
            if sys.platform == "win32":
                os.startfile(path)  # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])
            else:
                subprocess.Popen(["xdg-open", path])
        except Exception as exc:
            self.set_footer(f"打不开：{exc}")

    def copy_address(self):
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.addr_label.cget("text"))
            self.set_footer("地址已复制，可在手机 App 里手动粘贴连接")
        except Exception:
            pass

    # ---------------------------------------------------------- 轮询
    def _poll(self):
        try:
            while True:
                kind, payload = self.state.events.get_nowait()
                if kind == "photo":
                    self._on_photo(payload)
                elif kind == "dir":
                    self._refresh_dir_label()
                elif kind == "log":
                    self.set_footer(payload.get("text", ""))
                elif kind == "focus":
                    ip = payload.get("ip", "")
                    self.set_footer("只显示这台手机的照片（点「看全部」取消）" if ip else "显示全部手机的照片")
        except queue.Empty:
            pass

        self._refresh_status()
        self.root.after(160, self._poll)

    def _on_photo(self, item: dict):
        self.grid_view.refresh(force=True)
        self.set_footer(
            f"收到 {item['name']} · {human_size(item.get('size', 0))} · "
            f"{item['ms']:.0f} ms · {item.get('speed', 0):.1f} MB/s"
        )

    def _refresh_status(self):
        snap = self.state.snapshot()
        devices = snap["devices"]
        focus = snap["focus"]

        # 选中的手机掉线了就自动回到「全部」
        if focus and focus not in {d["ip"] for d in devices}:
            self.state.set_focus("")
            focus = ""

        online = (time.time() - snap["last_seen"]) < 12 and snap["last_seen"] > 0

        if online:
            alive = len(devices)
            name = devices[0]["name"] if len(devices) == 1 else ""
            if name:
                text = f"● 已连接 · {name}"
            else:
                text = f"● 已连接 · {alive} 台手机"
            color = OK
            self.link_text.configure(text=text.replace("● ", ""))
        else:
            text = "● 等待手机连接"
            color = WARN
            self.link_text.configure(text="等待手机连接")

        if text != self._last_status:
            self._last_status = text
            self.status_label.configure(text=text, fg=color)
            self.link_dot.delete("all")
            self.link_dot.create_oval(0, 0, 8, 8, fill=color, outline="")

        counts = (snap["count"], snap["total"], focus, len(devices))
        if counts != self._last_counts:
            self._last_counts = counts
            shown = [i for i in snap["items"] if not focus or i.get("ip") == focus]
            badge = f"{len(shown)} / {snap['count']} 张" if focus else f'{snap["count"]} 张'
            self.count_badge.configure(text=badge)
            self.stat_values["count"].configure(text=f'{snap["count"]}')
            self.stat_values["total"].configure(text=human_size(snap["total"]))
            self.stat_values["ms"].configure(
                text=f'{snap["last_ms"]:.0f} ms' if snap["last_ms"] else "—")
            self.stat_values["speed"].configure(
                text=f'{snap["last_speed"]:.1f} MB/s' if snap["last_speed"] else "—")
            if snap["client_ip"]:
                self.link_sub.configure(
                    text=f'手机 {snap["client_ip"]} · 直传端口 {self.port}')

        self._refresh_devices(devices, focus)

        items = snap["items"]
        if focus:
            items = [i for i in items if i.get("ip") == focus]
        self.grid_view.refresh(items)

    def _refresh_devices(self, devices, focus):
        tk = self.tk
        sig = (tuple((d["ip"], d["name"], d["count"]) for d in devices), focus)
        if sig == self._device_sig:
            return
        self._device_sig = sig

        for child in self.device_box.winfo_children():
            child.destroy()
        if not devices:
            return

        if len(devices) > 1:
            head = tk.Frame(self.device_box, bg=CARD)
            head.pack(fill="x", pady=(9, 4))
            tk.Label(head, text=f"在线手机 {len(devices)} 台",
                     bg=CARD, fg=SUB, font=(self.font, 8, "bold")).pack(side="left")
            if focus:
                btn = tk.Label(head, text="看全部", bg=CARD, fg=ACCENT,
                               font=(self.font, 8), cursor="hand2")
                btn.pack(side="right")
                btn.bind("<Button-1>", lambda e: self.state.set_focus(""))

        for dev in devices[:5]:
            selected = dev["ip"] == focus
            bg = mix_bg(ACCENT, 0.18, CARD2) if selected else CARD2
            row = tk.Frame(self.device_box, bg=bg,
                           highlightbackground=blend(STROKE, ACCENT, 0.6) if selected else STROKE,
                           highlightthickness=1, cursor="hand2")
            row.pack(fill="x", pady=(0, 4))

            avatar = tk.Canvas(row, width=26, height=26, bg=bg, highlightthickness=0)
            avatar.pack(side="left", padx=(7, 7), pady=6)
            avatar.create_oval(1, 1, 25, 25,
                               fill=hue_color(hue_from_id(dev["name"] + dev["ip"])),
                               outline="")
            avatar.create_text(13, 13, text=initial_of(dev["name"]), fill="#FFFFFF",
                               font=(self.font, 9, "bold"))

            col = tk.Frame(row, bg=bg)
            col.pack(side="left", fill="x", expand=True, pady=5)
            tk.Label(col, text=dev["name"], bg=bg, fg=TEXT, font=(self.font, 9, "bold"),
                     anchor="w").pack(fill="x")
            tk.Label(col, text=f'{dev["count"]} 张 · {dev["ip"]}', bg=bg, fg=MUTED,
                     font=(self.font, 8), anchor="w").pack(fill="x")

            if selected:
                tk.Label(row, text="只看这台", bg=bg, fg=ACCENT,
                         font=(self.font, 8)).pack(side="right", padx=8)

            ip = dev["ip"]
            targets = [row, avatar, col, *col.winfo_children()]
            for widget in targets:
                widget.bind("<Button-1>", lambda e, v=ip: self.state.set_focus(v))

    def run(self):
        self.root.mainloop()
