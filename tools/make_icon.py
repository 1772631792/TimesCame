#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TimesCam 图标生成器（二次元 · 大眼睛 + 渐变赛博底）。

一张母图同步产出：
    host/icon.ico                        Windows exe 图标（16~256 多尺寸）
    android/.../mipmap-*/ic_launcher.png Android 启动图标五档

用法：
    python tools/make_icon.py --out host
    python tools/make_icon.py --android app/android/app/src/main/res
    python tools/make_icon.py --png preview.png
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
    raise SystemExit("需要 Pillow：pip install Pillow")

BASE = 1024
MASTER = 2048

# 渐变：樱花粉 → 紫 → 电光青
GRAD_TL = (255, 143, 208)
GRAD_TR = (167, 116, 255)
GRAD_BL = (129, 94, 240)
GRAD_BR = (78, 216, 255)

EYE_DARK = (36, 16, 64, 255)
LASH = (26, 12, 40, 255)
WHITE = (255, 255, 255, 255)
IRIS_TOP = (140, 250, 255)
IRIS_BOTTOM = (108, 75, 255)
PUPIL = (22, 10, 38, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def diag_gradient(size: int) -> Image.Image:
    """低分辨率算好再放大，比逐像素画 2048² 快很多。"""
    small = 96
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        ty = y / (small - 1)
        left = lerp(GRAD_TL, GRAD_BL, ty)
        right = lerp(GRAD_TR, GRAD_BR, ty)
        for x in range(small):
            px[x, y] = lerp(left, right, x / (small - 1))
    return img.resize((size, size), Image.BICUBIC)


def radial_glow(size: int, color, center, radius: float, max_alpha: int, steps: int = 90) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = center
    for i in range(steps):
        k = i / (steps - 1)
        r = radius * (1 - k)
        alpha = int(max_alpha * (k ** 1.8))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
    return layer


def rounded_mask(size: int, radius: int, inset: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1), radius=radius, fill=255
    )
    return mask


def eye_polygon(cx, cy, half_w, top_h, bottom_h, n=180):
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((cx - half_w + 2 * half_w * t, cy - top_h * math.sin(math.pi * t) ** 0.92))
    for i in range(n + 1):
        t = 1 - i / n
        pts.append((cx - half_w + 2 * half_w * t, cy + bottom_h * math.sin(math.pi * t) ** 1.12))
    return pts


def curve(cx, cy, half_w, h, sign=1, n=180):
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((cx - half_w + 2 * half_w * t, cy + sign * h * math.sin(math.pi * t) ** 0.92))
    return pts


def thick_curve(draw, pts, width, fill):
    """Pillow 的 line 没有圆头，逐点补圆才不会出现锯齿/缺口。"""
    draw.line(pts, fill=fill, width=width, joint="curve")
    r = width / 2.0
    step = max(1, len(pts) // 90)
    for i in range(0, len(pts), step):
        x, y = pts[i]
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def star(draw, cx, cy, r, color, waist=0.2):
    pts = [
        (cx, cy - r),
        (cx + r * waist, cy - r * waist),
        (cx + r, cy),
        (cx + r * waist, cy + r * waist),
        (cx, cy + r),
        (cx - r * waist, cy + r * waist),
        (cx - r, cy),
        (cx - r * waist, cy - r * waist),
    ]
    draw.polygon(pts, fill=color)


def render(size: int = MASTER) -> Image.Image:
    k = size / BASE
    s = lambda v: int(round(v * k))  # noqa: E731

    # ---------- 底：渐变 + 圆角
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = rounded_mask(size, s(228), s(26))
    canvas.paste(diag_gradient(size), (0, 0), mask)

    # 左上柔光 + 右下暗角，让平面渐变有体积感
    canvas = Image.alpha_composite(
        canvas, _clip(radial_glow(size, (255, 255, 255), (s(300), s(250)), s(620), 90), mask)
    )
    canvas = Image.alpha_composite(
        canvas, _clip(radial_glow(size, (30, 10, 70), (s(860), s(880)), s(700), 70), mask)
    )

    # ---------- 眼睛（整体放大一点，压住视觉中心）
    ex, ey = s(512), s(508)
    half_w, top_h, bottom_h = s(340), s(206), s(166)
    eye = eye_polygon(ex, ey, half_w, top_h, bottom_h, n=200)
    eye_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(eye_mask).polygon(eye, fill=255)

    # 眼白：上白下粉
    sclera = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sclera)
    for y in range(size):
        t = max(0.0, min(1.0, (y - (ey - top_h)) / (top_h + bottom_h)))
        sd.line([(0, y), (size, y)], fill=(255, int(255 - 18 * t), int(255 - 6 * t), 255))
    canvas = Image.alpha_composite(canvas, _clip(sclera, eye_mask))

    # 虹膜
    iris_r = s(214)
    iris = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    idraw = ImageDraw.Draw(iris)
    steps = 150
    for i in range(steps, 0, -1):
        r = iris_r * i / steps
        t = 1 - i / steps
        idraw.ellipse(
            [ex - r, ey - r, ex + r, ey + r],
            fill=lerp(IRIS_TOP, IRIS_BOTTOM, t) + (255,),
        )

    # 虹膜放射纹（二次元那种一圈细刺）
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    for i in range(64):
        ang = i * math.pi * 2 / 64
        r0 = iris_r * 0.34
        r1 = iris_r * (0.72 + 0.24 * ((i * 7) % 5) / 4)
        rd.line(
            [(ex + math.cos(ang) * r0, ey + math.sin(ang) * r0),
             (ex + math.cos(ang) * r1, ey + math.sin(ang) * r1)],
            fill=(200, 245, 255, 40 if i % 2 else 22),
            width=s(3),
        )
    iris = Image.alpha_composite(iris, ring)
    idraw = ImageDraw.Draw(iris)
    idraw.ellipse([ex - iris_r, ey - iris_r, ex + iris_r, ey + iris_r],
                  outline=(44, 22, 82, 210), width=s(9))
    idraw.ellipse([ex - iris_r * 0.86, ey - iris_r * 0.86, ex + iris_r * 0.86, ey + iris_r * 0.86],
                  outline=(255, 255, 255, 40), width=s(4))

    # 瞳孔 + 底部反光
    pupil_r = iris_r * 0.44
    idraw.ellipse([ex - pupil_r, ey - pupil_r, ex + pupil_r, ey + pupil_r], fill=PUPIL)
    glow_bottom = radial_glow(size, IRIS_TOP, (ex, ey + iris_r * 0.34), iris_r * 0.62, 120)
    iris = Image.alpha_composite(iris, _clip(glow_bottom, eye_mask))

    # 高光
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.ellipse([ex - s(150), ey - s(168), ex - s(18), ey - s(58)], fill=(255, 255, 255, 235))
    hd.ellipse([ex + s(44), ey + s(56), ex + s(96), ey + s(108)], fill=(255, 255, 255, 210))
    hd.ellipse([ex - s(178), ey + s(46), ex - s(150), ey + s(74)], fill=(255, 255, 255, 170))
    iris = Image.alpha_composite(iris, hl)

    canvas = Image.alpha_composite(canvas, _clip(iris, eye_mask))

    # ---------- 眼线 / 睫毛 / 眉毛
    line = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)

    upper = curve(ex, ey, half_w, top_h, sign=-1, n=200)
    inner = [(x, y + s(58) * math.sin(math.pi * (i / 200)) ** 0.55) for i, (x, y) in enumerate(upper)]
    lid = upper + list(reversed(inner))
    ld.polygon(lid, fill=EYE_DARK)

    # 外眼角上挑
    ld.polygon(
        [(ex + half_w - s(8), ey - s(14)), (ex + half_w + s(56), ey - s(80)),
         (ex + half_w + s(16), ey + s(24))],
        fill=LASH,
    )

    # 睫毛：沿着上眼线根部往外挑，长度递减
    for i, t in enumerate((0.80, 0.88, 0.95)):
        x0 = ex - half_w + 2 * half_w * t
        y0 = ey - top_h * math.sin(math.pi * t) ** 0.92
        ln = s(84) - i * s(16)
        ld.line([(x0, y0), (x0 + ln * 0.62, y0 - ln)], fill=LASH, width=s(15 - i * 3))

    # 下眼线
    lower = curve(ex, ey, half_w * 0.97, bottom_h, sign=1, n=200)
    thick_curve(ld, lower[8:-8], s(8), (44, 22, 82, 150))

    # 眉毛：离眼睛近一点，保持干净的一条
    brow = curve(ex + s(10), ey - top_h - s(52), half_w * 0.7, s(48), sign=-1, n=140)
    thick_curve(ld, brow, s(26), (58, 26, 92, 235))

    canvas = Image.alpha_composite(canvas, line)

    # ---------- 星星闪光
    spark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(spark)
    star(draw, s(214), s(232), s(88), (255, 255, 255, 240))
    star(draw, s(806), s(196), s(54), (255, 255, 255, 215))
    star(draw, s(852), s(742), s(40), (255, 246, 255, 200))
    star(draw, s(178), s(742), s(26), (255, 255, 255, 170))
    canvas = Image.alpha_composite(canvas, spark)

    # 星星的柔光（先放大再模糊，省时间）
    soft = spark.filter(ImageFilter.GaussianBlur(s(14)))
    canvas = Image.alpha_composite(canvas, soft)

    # ---------- 圆角外的边缘光
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        (s(26), s(26), size - s(26) - 1, size - s(26) - 1),
        radius=s(228), outline=(255, 255, 255, 58), width=s(10),
    )
    canvas = Image.alpha_composite(canvas, edge)

    # 最后裁一次透明底，保证边角干净
    canvas.putalpha(Image.composite(canvas.getchannel("A"), Image.new("L", (size, size), 0), mask))
    return canvas


def _clip(layer: Image.Image, mask: Image.Image) -> Image.Image:
    filled = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    filled.paste(layer, (0, 0), mask)
    return filled


def build_ico(path: Path, master: Image.Image) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    sizes = [256, 128, 64, 48, 32, 16]
    frames = [master.resize((sz, sz), Image.LANCZOS) for sz in sizes]
    frames[0].save(path, format="ICO", sizes=[(sz, sz) for sz in sizes], append_images=frames[1:])
    return path


def build_png(path: Path, master: Image.Image, size: int = 512) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    master.resize((size, size), Image.LANCZOS).save(path)
    return path


def build_android_icons(res_dir: Path, master: Image.Image) -> list[Path]:
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    written = []
    for folder, px in densities.items():
        target = res_dir / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(target)
        written.append(target)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 TimesCam 二次元图标")
    parser.add_argument("--out", default="", help="输出目录（写 icon.ico + icon.png）")
    parser.add_argument("--android", default="", help="Android res 目录（写 mipmap-*）")
    parser.add_argument("--png", default="", help="额外导出预览 PNG")
    parser.add_argument("--size", type=int, default=0, help="预览 PNG 尺寸")
    args = parser.parse_args()

    master = render(MASTER)
    print(f"[icon] 母图 {MASTER}px 生成完毕")

    if args.out:
        ico = build_ico(Path(args.out) / "icon.ico", master)
        png = build_png(Path(args.out) / "icon.png", master, 512)
        print(f"[icon] {ico}")
        print(f"[icon] {png}")

    if args.android:
        for p in build_android_icons(Path(args.android), master):
            print(f"[icon] {p}")

    if args.png:
        size = args.size or 512
        print(f"[icon] {build_png(Path(args.png), master, size)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
