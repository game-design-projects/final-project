"""Cuts the reference images for the intro-video prompt (docs/intro/seedance-prompt.md) out of the game's own atlases.

The atlases keep the line in the luminance channel and the silhouette in alpha (see docs/ART.md), so a reference is the
frame put on black and tinted the way the game tints it. Run: uv run --with pillow python tools/intro_refs.py
"""
from pathlib import Path
from PIL import Image

ART = Path("assets/art")
OUT = Path("docs/intro/refs")
OUT.mkdir(parents=True, exist_ok=True)


def on_black(name: str, box: tuple, tint: str) -> Image.Image:
    sheet = Image.open(ART / f"{name}.png").convert("LA").crop(box)
    line = Image.composite(sheet.getchannel("L"), Image.new("L", sheet.size, 0), sheet.getchannel("A"))
    rgb = tuple(int(tint[i:i + 2], 16) for i in (1, 3, 5))
    return Image.merge("RGB", [line.point(lambda v, c=c: v * c // 255) for c in rgb])


def pad(im: Image.Image, size: int) -> Image.Image:
    """Centre the frame on a square of black, scaled up to fill 80% of it."""
    k = size * 0.8 / max(im.size)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    out = Image.new("RGB", (size, size))
    out.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
    return out


# the keyart is already white on black
Image.open(ART / "keyart.png").convert("RGB").save(OUT / "1_corridor_keyart.png")
# the heart-lock chest (props sheet, top left), in the gold the game uses for "mercy" (palette.gd MERCY)
pad(on_black("props", (10, 12, 145, 128), "#ffd27a"), 512).save(OUT / "2_chest.png")
# Wick: idle (row 0) and happy with the heart (row 2, last frame), tinted her friend colour (data/friends.json)
cw, ch = 1104 // 6, 1412 // 8
pad(on_black("witch", (0, 0, cw, ch), "#8fe8d8"), 512).save(OUT / "3_wick_idle.png")
pad(on_black("witch", (5 * cw, 2 * ch, 6 * cw, 3 * ch), "#8fe8d8"), 512).save(OUT / "4_wick_heart.png")
# wall things (decor sheet): barred window with a moon, skull window (smiling), hanging bat, heart banner
parts = [(30, 245, 250, 470), (575, 245, 785, 470), (885, 485, 990, 708), (570, 20, 780, 220)]
tiles = [on_black("decor", b, "#e8e2d0") for b in parts]
sheet = Image.new("RGB", (1024, 256))
for i, t in enumerate(tiles):
    t.thumbnail((250, 250))
    sheet.paste(t, (i * 256 + (256 - t.width) // 2, (256 - t.height) // 2))
sheet.save(OUT / "5_wall_things.png")
print("wrote", *sorted(p.name for p in OUT.iterdir()))
