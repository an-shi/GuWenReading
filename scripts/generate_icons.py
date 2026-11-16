"""生成古文阅读器桌面/Tauri 图标资源，无需外部设计工具。"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "desktop" / "src-tauri" / "icons"
FONT_CANDIDATES = [
    Path("C:/Windows/Fonts/simhei.ttf"),
    Path("C:/Windows/Fonts/msyhbd.ttc"),
    Path("C:/Windows/Fonts/simsun.ttc"),
]


def font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def make_icon(size: int) -> Image.Image:
    scale = 4
    canvas = size * scale
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    margin = round(canvas * 0.055)
    radius = round(canvas * 0.2)
    draw.rounded_rectangle(
        (margin, margin, canvas - margin, canvas - margin),
        radius=radius,
        fill=(18, 31, 27, 255),
    )
    inner = round(canvas * 0.105)
    draw.rounded_rectangle(
        (inner, inner, canvas - inner, canvas - inner),
        radius=round(radius * 0.8),
        outline=(199, 154, 94, 255),
        width=max(2, round(canvas * 0.008)),
    )
    glyph_font = font(round(canvas * 0.47))
    text = "古"
    box = draw.textbbox((0, 0), text, font=glyph_font)
    width = box[2] - box[0]
    height = box[3] - box[1]
    draw.text(
        ((canvas - width) / 2 - box[0], (canvas - height) / 2 - box[1] - canvas * 0.015),
        text,
        font=glyph_font,
        fill=(241, 232, 216, 255),
    )
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    ICONS.mkdir(parents=True, exist_ok=True)
    sizes = {
        "32x32.png": 32,
        "128x128.png": 128,
        "128x128@2x.png": 256,
        "icon.png": 512,
    }
    for filename, size in sizes.items():
        icon = make_icon(size)
        icon.save(ICONS / filename)
    make_icon(256).save(
        ICONS / "icon.ico",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    # Mobile launcher icon source (flutter_launcher_icons generates platform sets).
    mobile_assets = ROOT / "mobile" / "assets"
    mobile_assets.mkdir(parents=True, exist_ok=True)
    make_icon(1024).save(mobile_assets / "icon.png")
    print(f"Wrote icons to {ICONS} and {mobile_assets / 'icon.png'}")


if __name__ == "__main__":
    main()
