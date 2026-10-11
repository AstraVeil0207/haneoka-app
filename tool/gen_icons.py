"""Launcher icons for every platform from the website favicon.

Usage: python3 tool/gen_icons.py   (needs rsvg-convert and ImageMagick)

The favicon is a navy disc; each platform gets it unchanged in the shape it
expects: Android an adaptive icon (navy background, the disc inside the 66 dp
safe circle) plus legacy mipmaps, iOS an opaque square, macOS and Windows the
disc on transparency.
"""
import json, re, subprocess, tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
favicon = root / "assets/brand/favicon.svg"
NAVY = "#31356E"
svg = favicon.read_text()
inner = re.sub(r"^.*?<svg[^>]*>|</svg>\s*$", "", svg, flags=re.S)


def render(source, out, size):
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(source), "-o", str(out)], check=True)


def framed(name, canvas, disc, background=None):
    """The disc `disc` units wide, centred on a `canvas`-unit square."""
    offset = (canvas - disc) / 2
    fill = f'<rect width="{canvas}" height="{canvas}" fill="{background}"/>' if background else ""
    path = Path(tmp) / f"{name}.svg"
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {canvas} {canvas}">{fill}'
        f'<svg x="{offset}" y="{offset}" width="{disc}" height="{disc}" viewBox="0 0 696 696">{inner}</svg></svg>'
    )
    return path


with tempfile.TemporaryDirectory() as tmp:
    # Android: adaptive layers are 108 dp, of which 72 dp show and 66 dp are safe.
    res = root / "android/app/src/main/res"
    foreground = framed("foreground", 108, 72)
    for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        render(favicon, res / f"mipmap-{density}/ic_launcher.png", int(48 * scale))
        render(foreground, res / f"mipmap-{density}/ic_launcher_foreground.png", int(108 * scale))
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{NAVY}</color>\n</resources>\n'
    )

    # iOS: opaque squares; the system rounds the corners.
    ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    square = framed("square", 696, 696, NAVY)
    for image in json.loads((ios / "Contents.json").read_text())["images"]:
        points = float(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        out = ios / image["filename"]
        render(square, out, round(points * scale))
        subprocess.run(["magick", str(out), "-background", NAVY, "-alpha", "remove", "-alpha", "off", str(out)], check=True)

    # macOS: the disc inside Apple's 824-of-1024 icon grid.
    mac = root / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    grid = framed("mac", 1024, 824)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        render(grid, mac / f"app_icon_{size}.png", size)

    # Windows: the disc, edge to edge.
    sizes = (16, 24, 32, 48, 64, 128, 256)
    pngs = []
    for size in sizes:
        render(favicon, Path(tmp) / f"win{size}.png", size)
        pngs.append(str(Path(tmp) / f"win{size}.png"))
    subprocess.run(["magick", *pngs, str(root / "windows/runner/resources/app_icon.ico")], check=True)
