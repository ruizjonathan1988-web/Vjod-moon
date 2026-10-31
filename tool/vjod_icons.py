"""Draws the VJOD icons (iPad app and Safari home-screen version) from
assets/images/vjod_logo.png: the red logo centred on black.

Run from the repository root: python3 tool/vjod_icons.py
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = Image.open(ROOT / "assets/images/vjod_logo.png").convert("RGBA")
LOGO = LOGO.crop(LOGO.getbbox())


def icon(size, logo_share=0.8):
    """A square icon, logo taking [logo_share] of the width, no transparency."""
    big = 1024
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 255))
    w = int(big * logo_share)
    h = round(LOGO.height * w / LOGO.width)
    canvas.alpha_composite(LOGO.resize((w, h), Image.LANCZOS), ((big - w) // 2, (big - h) // 2))
    return canvas.convert("RGB").resize((size, size), Image.LANCZOS)


ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for entry in json.loads((ios / "Contents.json").read_text())["images"]:
    name = entry.get("filename")
    if not name:
        continue
    points = float(entry["size"].split("x")[0])
    scale = int(entry["scale"].rstrip("x"))
    icon(round(points * scale)).save(ios / name)

web = ROOT / "web/icons"
icon(192).save(web / "Icon-192.png")
icon(512).save(web / "Icon-512.png")
# Maskable icons get cropped to a circle: the logo stays inside the safe zone.
icon(192, 0.62).save(web / "Icon-maskable-192.png")
icon(512, 0.62).save(web / "Icon-maskable-512.png")
icon(180).save(web / "apple-touch-icon.png")
icon(32).save(ROOT / "web/favicon.png")
