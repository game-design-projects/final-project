#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=11"]
# ///
"""Cuts the character references the story CGs are drawn from (tools/art/prompts/cg_*.txt) out of the source sheets.

Each reference is one cell of a sheet in tools/art/source/, white line on black, centred on a 512 square, so Codex sees the
character as the game draws it. They go to tools/art/raw/refs/ (git-ignored, made again whenever needed):
  uv run --script tools/art/cg_refs.py
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source"
OUT = HERE / "raw" / "refs"

# name: (sheet, cols, rows, cell)
REFS = {
    "wick": ("witch.set1", 6, 4, 0),
    "dragon": ("dragon.set1", 6, 4, 0),
    "slime": ("slime.set1", 6, 4, 0),
    "bandit": ("bandit.set1", 6, 4, 0),
    "snake": ("snake.set1", 6, 4, 0),
    "rock": ("rock.set1", 6, 4, 0),
    "trader": ("trader.set1", 6, 4, 0),
    "lord_slime": ("lords", 2, 2, 0),
    "lord_bandit": ("lords", 2, 2, 1),
    "lord_rock": ("lords", 2, 2, 2),
    "lord_snake": ("lords", 2, 2, 3),
    "chest": ("props", 4, 3, 0),
}


def cut(sheet: str, cols: int, rows: int, cell: int) -> Image.Image:
    im = Image.open(SOURCE / f"{sheet}.png").convert("L")
    w, h = im.width // cols, im.height // rows
    x, y = cell % cols * w, cell // cols * h
    part = im.crop((x, y, x + w, y + h))
    box = part.point(lambda v: 255 if v > 40 else 0).getbbox() or (0, 0, w, h)
    part = part.crop(box)
    k = 512 * 0.8 / max(part.size)
    part = part.resize((max(1, round(part.width * k)), max(1, round(part.height * k))), Image.LANCZOS)
    out = Image.new("L", (512, 512))
    out.paste(part, ((512 - part.width) // 2, (512 - part.height) // 2))
    return out.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    Image.open(SOURCE / "keyart.png").convert("RGB").save(OUT / "style.png")
    for name, spec in REFS.items():
        cut(*spec).save(OUT / f"{name}.png")
    print("cg_refs:", OUT, "style", *REFS)


if __name__ == "__main__":
    main()
