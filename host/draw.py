# -*- coding: utf-8 -*-
"""Tkinter 手绘组件：渐变按钮、圆角背景、照片缩略图网格。"""

from __future__ import annotations

import time
from datetime import datetime

from config import human_size
from theme import (
    ACCENT,
    ACCENT2,
    BG,
    CARD,
    CARD2,
    MUTED,
    PANEL,
    STROKE,
    SUB,
    TEXT,
    TILE,
)

try:
    from PIL import Image, ImageDraw, ImageOps, ImageTk  # type: ignore

    PIL_OK = True
except Exception:  # Pillow 只影响缩略图
    PIL_OK = False
    Image = ImageDraw = ImageOps = ImageTk = None  # type: ignore


# ---------------------------------------------------------------- 颜色


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def rgb_hex(rgb: tuple[int, int, int]) -> str:
    r, g, b = (max(0, min(255, int(v))) for v in rgb)
    return f"#{r:02x}{g:02x}{b:02x}"


def blend(c1: str, c2: str, t: float) -> str:
    a, b = hex_rgb(c1), hex_rgb(c2)
    return rgb_hex((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t))


def mix_bg(color: str, t: float, base: str = CARD) -> str:
    return blend(base, color, t)


def corner_inset(y: int, h: int, r: int) -> int:
    if y < r:
        dy = r - y
    elif y > h - 1 - r:
        dy = y - (h - 1 - r)
    else:
        return 0
    dy = max(0, min(r, dy))
    return r - int((r * r - dy * dy) ** 0.5)


def draw_gradient_round(canvas, w: int, h: int, r: int, c1: str, c2: str) -> None:
    """按行画渐变，两端按圆角收边——比方角贴图自然。"""
    if w <= 1 or h <= 1:
        return
    r = max(0, min(r, h // 2, w // 2))
    for y in range(h):
        inset = corner_inset(y, h, r)
        canvas.create_line(inset, y, w - inset, y, fill=blend(c1, c2, y / max(1, h - 1)))


# ---------------------------------------------------------------- 按钮


class GradientButton:
    """Canvas 手绘圆角渐变按钮。"""

    def __init__(self, master, text, command=None, width=150, height=38,
                 colors=(ACCENT, ACCENT2), bg=BG, font=None):
        import tkinter as tk

        self.text = text
        self.command = command
        self.colors = colors
        self._hover = False
        self._pressed = False
        self.font = font
        self.canvas = tk.Canvas(master, width=width, height=height, bg=bg,
                                highlightthickness=0, bd=0, cursor="hand2")
        self._redraw()
        self.canvas.bind("<Configure>", lambda e: self._redraw())
        self.canvas.bind("<Enter>", self._on_enter)
        self.canvas.bind("<Leave>", self._on_leave)
        self.canvas.bind("<ButtonPress-1>", self._on_press)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)

    def pack(self, **kw):
        self.canvas.pack(**kw)
        return self

    def grid(self, **kw):
        self.canvas.grid(**kw)
        return self

    def set_text(self, text: str) -> None:
        self.text = text
        self._redraw()

    def _on_enter(self, _=None):
        self._hover = True
        self._redraw()

    def _on_leave(self, _=None):
        self._hover = False
        self._pressed = False
        self._redraw()

    def _on_press(self, _=None):
        self._pressed = True
        self._redraw()

    def _on_release(self, _=None):
        was_pressed = self._pressed
        self._pressed = False
        self._redraw()
        if was_pressed and self.command:
            self.command()

    def _redraw(self):
        w = self.canvas.winfo_width()
        h = self.canvas.winfo_height()
        if w <= 1:
            w, h = int(self.canvas["width"]), int(self.canvas["height"])
        self.canvas.delete("all")
        c1, c2 = self.colors
        if self._hover:
            c1, c2 = blend(c1, "#FFFFFF", 0.16), blend(c2, "#FFFFFF", 0.16)
        if self._pressed:
            c1, c2 = blend(c1, "#000000", 0.16), blend(c2, "#000000", 0.16)
        draw_gradient_round(self.canvas, w, h, h // 2, c1, c2)
        self.canvas.create_text(w / 2, h / 2 + 0.5, text=self.text, fill="#FFFFFF",
                                font=self.font or ("Segoe UI", 10, "bold"))


class GhostButton:
    """描边幽灵按钮。"""

    def __init__(self, master, text, command=None, width=96, height=38, bg=CARD, font=None,
                 fg=SUB):
        import tkinter as tk

        self.text = text
        self.command = command
        self.bg = bg
        self.fg = fg
        self._hover = False
        self.font = font
        self.canvas = tk.Canvas(master, width=width, height=height, bg=bg,
                                highlightthickness=0, bd=0, cursor="hand2")
        self._redraw()
        self.canvas.bind("<Configure>", lambda e: self._redraw())
        self.canvas.bind("<Enter>", self._enter)
        self.canvas.bind("<Leave>", self._leave)
        self.canvas.bind("<Button-1>", lambda e: self.command and self.command())

    def pack(self, **kw):
        self.canvas.pack(**kw)
        return self

    def grid(self, **kw):
        self.canvas.grid(**kw)
        return self

    def _enter(self, _=None):
        self._hover = True
        self._redraw()

    def _leave(self, _=None):
        self._hover = False
        self._redraw()

    def _redraw(self):
        w = self.canvas.winfo_width()
        h = self.canvas.winfo_height()
        if w <= 1:
            w, h = int(self.canvas["width"]), int(self.canvas["height"])
        self.canvas.delete("all")
        fill = blend(self.bg, "#FFFFFF", 0.09) if self._hover else blend(self.bg, "#FFFFFF", 0.04)
        draw_gradient_round(self.canvas, w, h, h // 2, fill, fill)
        self.canvas.create_text(w / 2, h / 2 + 0.5, text=self.text,
                                fill=TEXT if self._hover else self.fg,
                                font=self.font or ("Segoe UI", 10))


# ---------------------------------------------------------------- 照片墙


class PhotoGrid:
    """右侧缩略图网格，新照片排最前，滚轮滚动。"""

    def __init__(self, master, state, font: str, on_open):
        import tkinter as tk

        self.state = state
        self.font = font
        self.on_open = on_open

        self.canvas = tk.Canvas(master, bg=PANEL, highlightthickness=0, bd=0)
        self.canvas.pack(side="left", fill="both", expand=True)

        self.inner = tk.Frame(self.canvas, bg=PANEL)
        self._win = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.inner.bind("<Configure>", self._sync_scroll)
        self.canvas.bind("<Configure>", self._on_resize)
        self.canvas.bind("<Enter>", lambda e: self.canvas.bind_all("<MouseWheel>", self._wheel))
        self.canvas.bind("<Leave>", lambda e: self.canvas.unbind_all("<MouseWheel>"))

        self._imgs: dict[str, object] = {}
        self._cols = 0
        self._signature = None

    def _wheel(self, event):
        self.canvas.yview_scroll(int(-event.delta / 120), "units")

    def _sync_scroll(self, _=None):
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_resize(self, event):
        self.canvas.itemconfigure(self._win, width=event.width)
        cols = max(1, (event.width - 12) // (TILE + 12))
        if cols != self._cols:
            self._cols = cols
            self.refresh(force=True)

    def refresh(self, items=None, force: bool = False):
        if items is None:
            items = self.state.snapshot()["items"]
        signature = (len(items), items[0]["path"] if items else "")
        if not force and signature == self._signature:
            return
        self._signature = signature

        if self._cols <= 0:
            width = self.canvas.winfo_width()
            self._cols = max(1, (width - 12) // (TILE + 12)) if width > 1 else 4

        for child in self.inner.winfo_children():
            child.destroy()

        if not items:
            self._empty()
            return

        for index, item in enumerate(items):
            row, col = divmod(index, self._cols)
            self._tile(item, newest=index == 0).grid(
                row=row, column=col, padx=6, pady=6, sticky="n")

    def _empty(self):
        import tkinter as tk

        holder = tk.Frame(self.inner, bg=PANEL)
        holder.grid(row=0, column=0, columnspan=max(1, self._cols), pady=90)
        ring = tk.Canvas(holder, width=96, height=96, bg=PANEL, highlightthickness=0)
        ring.pack()
        for i in range(3):
            ring.create_oval(8 + i * 13, 8 + i * 13, 88 - i * 13, 88 - i * 13,
                             outline=blend(PANEL, ACCENT, 0.1 + i * 0.07), width=1)
        ring.create_text(48, 48, text="JPG", fill=blend(PANEL, ACCENT, 0.75),
                         font=(self.font, 12, "bold"))
        tk.Label(holder, text="等待手机拍照", bg=PANEL, fg=TEXT,
                 font=(self.font, 13, "bold")).pack(pady=(14, 4))
        tk.Label(holder, text="拍完的照片会立刻出现在这里，并保存到左侧文件夹",
                 bg=PANEL, fg=MUTED, font=(self.font, 9)).pack()

    def _thumb(self, path: str):
        if not PIL_OK:
            return None
        if path in self._imgs:
            return self._imgs[path]
        try:
            im = Image.open(path)
            im.draft("RGB", (TILE * 2, TILE * 2))
            im = im.convert("RGB")
            im = ImageOps.fit(im, (TILE, TILE), method=Image.LANCZOS)
            mask = Image.new("L", (TILE * 4, TILE * 4), 0)
            ImageDraw.Draw(mask).rounded_rectangle(
                (0, 0, TILE * 4 - 1, TILE * 4 - 1), radius=TILE // 4, fill=255)
            mask = mask.resize((TILE, TILE), Image.LANCZOS)
            out = Image.new("RGB", (TILE, TILE), hex_rgb(CARD2))
            out.paste(im, (0, 0), mask)
            photo = ImageTk.PhotoImage(out)
            if len(self._imgs) > 260:
                self._imgs.clear()
            self._imgs[path] = photo
            return photo
        except Exception:
            return None

    def _tile(self, item: dict, newest: bool = False):
        import tkinter as tk

        border = blend(STROKE, ACCENT, 0.55) if newest else STROKE
        card = tk.Frame(self.inner, bg=CARD, highlightbackground=border, highlightthickness=1)

        photo = self._thumb(item["path"])
        if photo is not None:
            label = tk.Label(card, image=photo, bg=CARD, bd=0)
            label.image = photo
            label.pack(padx=4, pady=(4, 0))
        else:
            ph = tk.Canvas(card, width=TILE, height=TILE, bg=CARD2, highlightthickness=0)
            ph.pack(padx=4, pady=(4, 0))
            ph.create_text(TILE // 2, TILE // 2 - 8, text="JPG",
                           fill=blend(CARD2, ACCENT, 0.7), font=(self.font, 14, "bold"))
            ph.create_text(TILE // 2, TILE // 2 + 14, text="装 Pillow 可显示缩略图",
                           fill=MUTED, font=(self.font, 8))

        meta = tk.Frame(card, bg=CARD)
        meta.pack(fill="x", padx=8, pady=(7, 8))
        stamp = datetime.fromtimestamp(item.get("at", time.time())).strftime("%H:%M:%S")
        tk.Label(meta, text=stamp, bg=CARD, fg=TEXT, font=(self.font, 10, "bold"),
                 anchor="w").pack(fill="x")
        tk.Label(meta, text=f'{human_size(item.get("size", 0))} · {item.get("ms", 0):.0f} ms',
                 bg=CARD, fg=SUB, font=(self.font, 8), anchor="w").pack(fill="x")

        path = item["path"]
        for widget in [card, meta, *card.winfo_children()]:
            if isinstance(widget, tk.Canvas):
                continue
            widget.bind("<Button-1>", lambda e, p=path: self.on_open(p))
        return card
