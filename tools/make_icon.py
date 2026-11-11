#!/usr/bin/env python3
"""Draw Anchor's app icon and write the macOS AppIcon asset catalog.

A gold anchor whose stock forms a cross ("hope... as an anchor of the soul",
Hebrews 6:19) on a warm parchment tile, following the macOS icon grid
(824 pt tile on a 1024 pt canvas, with a soft drop shadow).

Usage: python3 tools/make_icon.py [out_dir=Anchor/Assets.xcassets]
"""
import json, math, pathlib, sys
from PIL import Image, ImageDraw, ImageFilter

SS = 4                      # supersampling factor
S = 1024 * SS
U = lambda v: int(round(v * SS))

def squircle(cx, cy, half, n=5.0, steps=720):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = half * math.copysign(abs(c) ** (2 / n), c)
        y = half * math.copysign(abs(s) ** (2 / n), s)
        pts.append((cx + x, cy + y))
    return pts

def vgradient(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))

def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def draw_icon():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile = squircle(U(512), U(512), U(412))

    # Drop shadow
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).polygon([(x, y + U(10)) for x, y in tile], fill=95)
    shadow = shadow.filter(ImageFilter.GaussianBlur(U(14)))
    canvas.paste((40, 28, 12, 255), (0, 0), shadow)

    # Parchment tile
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(tile, fill=255)
    bg = vgradient((S, S), hexrgb("#FBF5E8"), hexrgb("#E9D6B0")).convert("RGBA")
    canvas.paste(bg, (0, 0), mask)

    # Soft inner glow near the top and a hairline rim
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([U(180), U(60), U(844), U(520)], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(U(80)))
    glow = Image.composite(glow, Image.new("L", (S, S), 0), mask)
    canvas.paste((255, 255, 255, 255), (0, 0), glow)
    rim = ImageDraw.Draw(canvas)
    rim.line(tile + [tile[0]], fill=(176, 140, 84, 90), width=U(3))

    # Anchor shape as a mask
    a = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(a)
    cx = 512
    # Ring
    d.ellipse([U(cx - 58), U(198), U(cx + 58), U(314)], fill=255)
    d.ellipse([U(cx - 31), U(225), U(cx + 31), U(287)], fill=0)
    # Shank
    d.rounded_rectangle([U(cx - 21), U(300), U(cx + 21), U(812)], radius=U(10), fill=255)
    # Stock (cross-bar), with rounded ends
    d.rounded_rectangle([U(cx - 150), U(372), U(cx + 150), U(414)], radius=U(21), fill=255)
    # Arms: a thick arc across the bottom
    r, cy = 236, 576
    d.arc([U(cx - r), U(cy - r), U(cx + r), U(cy + r)], start=18, end=162, fill=255, width=U(42))
    # Flukes (arrowheads) at both arm tips, pointing up and out
    for ang, side in ((18, 1), (162, -1)):
        rad = math.radians(ang)
        tx = cx + (r - 21) * math.cos(rad)
        ty = cy + (r - 21) * math.sin(rad)
        tip = (tx + side * 40, ty - 92)
        base1 = (tx - side * 44, ty + 20)
        base2 = (tx + side * 70, ty + 6)
        d.polygon([(U(p[0]), U(p[1])) for p in (tip, base1, base2)], fill=255)
    # Crown point at the bottom
    d.polygon([(U(cx - 46), U(800)), (U(cx + 46), U(800)), (U(cx), U(866))], fill=255)

    # Subtle engraved shadow under the anchor
    sh = a.filter(ImageFilter.GaussianBlur(U(6)))
    sh = Image.composite(sh, Image.new("L", (S, S), 0), mask).point(lambda v: int(v * 0.35))
    off = Image.new("L", (S, S), 0)
    off.paste(sh, (0, U(8)))
    canvas.paste((92, 60, 20, 255), (0, 0), off)

    # Gold gradient fill
    gold = vgradient((S, S), hexrgb("#C99A4E"), hexrgb("#8A5A24")).convert("RGBA")
    canvas.paste(gold, (0, 0), a)

    # Highlight along the top edges of the anchor
    hl = a.filter(ImageFilter.GaussianBlur(U(2)))
    inner = a.filter(ImageFilter.MinFilter(7)).transform(a.size, Image.AFFINE, (1, 0, 0, 0, 1, U(3)))
    hl = Image.composite(Image.new("L", (S, S), 0), hl, inner).point(lambda v: int(v * 0.45))
    canvas.paste((255, 236, 196, 255), (0, 0), hl)

    return canvas.resize((1024, 1024), Image.LANCZOS)

def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Anchor/Assets.xcassets")
    icon_dir = out / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    (out / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    master = draw_icon()
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(icon_dir / name)
            images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}", "filename": name})
    (icon_dir / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    master.save("tools/icon-preview.png")
    print("wrote", icon_dir)

main()
