# -*- coding: utf-8 -*-
"""深色主题配色与字体。"""

from __future__ import annotations

BG = "#070B12"
PANEL = "#0A1018"
CARD = "#111A28"
CARD2 = "#0D1521"
STROKE = "#1B2534"
TEXT = "#F2F6FF"
SUB = "#8996AA"
MUTED = "#5D6B80"
ACCENT = "#4F8CFF"
ACCENT2 = "#9B6BFF"
OK = "#35D07F"
WARN = "#FFB020"
ERR = "#FF5F6D"

TILE = 168

FONT_CANDIDATES = (
    "Microsoft YaHei UI",
    "Microsoft YaHei",
    "PingFang SC",
    "Noto Sans CJK SC",
    "Segoe UI",
)


def pick_font(tkfont) -> str:
    """挑一个能好好显示中文的系统字体。"""
    try:
        families = set(tkfont.families())
    except Exception:
        families = set()
    for name in FONT_CANDIDATES:
        if name in families:
            return name
    return "Segoe UI"
