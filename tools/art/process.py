#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=11", "numpy>=2", "scipy>=1.14"]
# ///
"""Turns the sheets Codex drew (tools/art/source/, white lines on black) into what the game loads.

Two kinds of sheet, both listed in sheets.json. A figure is continuous animation: <name>.set1.png and <name>.set2.png, each row one action
in equal cells. Anything else is one <name>.png of separate drawings. For each: cut it into cells (every stroke goes to the cell its
middle is nearest), line the frames up on the feet, work out a silhouette so the inside of a body hides what is behind it, and write
  assets/art/<name>.png        the atlas: L the line (white on black inside a body), A the silhouette
  data/sprites.json            where each frame is, where the feet are, how big it stands in the world, how each action plays
  docs/art/<name>.gif          a figure's whole reel in its colour, for looking at without running the game
  docs/art/<name>/<action>.gif each action on its own
It prints how far each frame moved from the one before, so a jump shows up without watching the whole set.

    uv run --script tools/art/process.py            # every sheet
    uv run --script tools/art/process.py slime      # one (the others stay as they are in data/sprites.json)
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = HERE / "source"
ATLAS_DIR = ROOT / "assets" / "art"
GIF_DIR = ROOT / "docs" / "art"
META = ROOT / "data" / "sprites.json"

LINE_AT = 0.28  # a pixel this bright is part of a stroke
GAP_CLOSE = 3  # strokes closer than this many source pixels count as joined when working out what a body encloses
PAD = 12  # empty pixels between atlas cells, so mipmaps of one frame don't bleed into the next


def load_gray(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0


def cut_cells(gray: np.ndarray, cols: int, rows: int) -> list[np.ndarray]:
    """One image per cell: every connected stroke goes whole to the cell whose middle is nearest its own middle."""
    h, w = gray.shape
    labels, count = ndi.label(gray > 0.12, structure=np.ones((3, 3)))
    cells = [np.zeros_like(gray) for _ in range(cols * rows)]
    if count == 0:
        return cells
    slices = ndi.find_objects(labels)
    for i, box in enumerate(slices):
        ys, xs = box
        cx, cy = (xs.start + xs.stop) / 2.0, (ys.start + ys.stop) / 2.0
        col = min(cols - 1, max(0, int(cx / w * cols)))
        row = min(rows - 1, max(0, int(cy / h * rows)))
        cell = cells[row * cols + col]
        mask = labels[box] == i + 1
        cell[box][mask] = gray[box][mask]
    return cells


def silhouette(cell: np.ndarray) -> np.ndarray:
    """Which pixels a body encloses (True), found by flooding in from the edge of the cell through whatever isn't a stroke."""
    line = ndi.binary_closing(cell > LINE_AT, iterations=GAP_CLOSE)
    outside, _ = ndi.label(~line)
    edge = set(np.unique(np.concatenate([outside[0], outside[-1], outside[:, 0], outside[:, -1]]))) - {0}
    return ~np.isin(outside, list(edge))


def body_box(cell: np.ndarray, closed: np.ndarray) -> tuple[int, int, int, int]:
    """(left, top, right, bottom) of the biggest enclosed thing in a cell: the body, not the marks round it."""
    labels, count = ndi.label(closed, structure=np.ones((3, 3)))
    if count == 0:
        ys, xs = np.nonzero(cell > LINE_AT)
        return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    sizes = ndi.sum_labels(closed, labels, index=np.arange(1, count + 1))
    ys, xs = ndi.find_objects(labels)[int(np.argmax(sizes))]
    return xs.start, ys.start, xs.stop, ys.stop


def rgba(cell: np.ndarray, closed: np.ndarray) -> np.ndarray:
    """Premultiplied line + silhouette for one cell: inside a body the fill is opaque black under the line, outside it the line's own
    brightness is its alpha."""
    line = np.clip(cell / 0.9, 0.0, 1.0)
    alpha = np.maximum(line, closed.astype(np.float32))
    return np.dstack([line, line, line, alpha])


def to_atlas_pixels(prem: np.ndarray) -> np.ndarray:
    """Straight alpha: white wherever nothing but a stroke's edge shows, so filtering never darkens a line's rim."""
    a = prem[..., 3]
    rgb = np.where(a[..., None] > 1e-4, prem[..., :3] / np.maximum(a[..., None], 1e-4), 1.0)
    return np.dstack([rgb, a])


def fit(prem: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    channels = [np.asarray(Image.fromarray(prem[..., i]).resize(size, Image.Resampling.LANCZOS)) for i in range(4)]
    return np.clip(np.dstack(channels), 0.0, 1.0)


def save_atlas(name: str, atlas: np.ndarray) -> Path:
    ATLAS_DIR.mkdir(parents=True, exist_ok=True)
    path = ATLAS_DIR / f"{name}.png"
    la = np.dstack([atlas[..., 0], atlas[..., 3]])
    Image.fromarray((np.clip(la, 0, 1) * 255 + 0.5).astype(np.uint8), "LA").save(path, optimize=True)
    return path


def continuity(frames: list[np.ndarray]) -> list[float]:
    """How much of what is drawn changes from one frame to the next, 0 (nothing) .. 1 (nothing in common)."""
    out = []
    for a, b in zip(frames, frames[1:]):
        x, y = a[..., 3] > 0.5, b[..., 3] > 0.5
        out.append(1.0 - float((x & y).sum()) / max(1.0, float((x | y).sum())))
    return out


def process_figure(name: str, spec: dict) -> dict:
    """A figure: every action of every set on one canvas with the same feet, one action to a row of the atlas."""
    rows = []
    for set_name, layout in spec["sets"].items():
        source = SOURCE / f"{name}.{set_name}.png"
        if not source.exists():
            print(f"  no {source.name}: its {', '.join(layout['anims'])} are left out")
            continue
        cols, nrows = layout["cols"], layout["rows"]
        gray = load_gray(source)
        cell_w = gray.shape[1] / cols
        cells = cut_cells(gray, cols, nrows)
        for r, anim in enumerate(layout["anims"]):
            shots = []
            for c in range(cols):
                cell = cells[r * cols + c]
                if cell.max() <= LINE_AT:
                    raise SystemExit(f"{name}.{anim}: frame {c + 1} is empty")
                closed = silhouette(cell)
                l, t, right, b = body_box(cell, closed)
                ys, xs = np.nonzero(cell > 0.08)
                share = float(closed.sum()) / float(max(1, (right - l) * (b - t)))
                if share < 0.3:
                    print(f"  WARNING {name}.{anim} frame {c + 1}: encloses only {share:.0%}: its outline may be open")
                shots.append({"cell": cell, "closed": closed, "centre": (l + right) / 2.0, "bottom": float(b), "top": float(t), "box": (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)})
            rule = spec["anims"][anim]
            for c, f in enumerate(shots):
                # `pin` holds the feet still frame by frame on each axis named; otherwise a frame stays where it was drawn against the row's first
                f["feet"] = (f["centre"] if "x" in rule.get("pin", "") else shots[0]["centre"] + c * cell_w, f["bottom"] if "y" in rule.get("pin", "") else shots[0]["bottom"])
            rows.append((anim, rule, shots))
    all_shots = [f for _, _, shots in rows for f in shots]
    left = max(f["feet"][0] - f["box"][0] for f in all_shots)
    right = max(f["box"][2] - f["feet"][0] for f in all_shots)
    up = max(f["feet"][1] - f["box"][1] for f in all_shots)
    down = max(f["box"][3] - f["feet"][1] for f in all_shots)
    src_w, src_h = int(np.ceil(left + right)) + 6, int(np.ceil(up + down)) + 6
    k = spec["cell_px"] / max(src_w, src_h)
    dst_w, dst_h = max(4, round(src_w * k)), max(4, round(src_h * k))
    cols = max(len(shots) for _, _, shots in rows)
    atlas = np.zeros(((dst_h + PAD) * len(rows) + PAD, (dst_w + PAD) * cols + PAD, 4), dtype=np.float32)
    atlas[..., :3] = 1.0
    anims = {}
    reel = []
    for r, (anim, rule, shots) in enumerate(rows):
        small = []
        for c, f in enumerate(shots):
            canvas = np.zeros((src_h, src_w, 4), dtype=np.float32)
            ox, oy = int(round(left + 3 - f["feet"][0])), int(round(up + 3 - f["feet"][1]))
            prem = rgba(f["cell"], f["closed"])
            x0, y0, x1, y1 = f["box"]
            x0, y0 = max(0, x0 - 2), max(0, y0 - 2)
            x1, y1 = min(prem.shape[1], x1 + 2), min(prem.shape[0], y1 + 2)
            tx0, ty0, tx1, ty1 = max(0, x0 + ox), max(0, y0 + oy), min(src_w, x1 + ox), min(src_h, y1 + oy)
            canvas[ty0:ty1, tx0:tx1] = prem[ty0 - oy : ty1 - oy, tx0 - ox : tx1 - ox]
            shot = fit(canvas, (dst_w, dst_h))
            small.append(shot)
            ax, ay = PAD + c * (dst_w + PAD), PAD + r * (dst_h + PAD)
            atlas[ay : ay + dst_h, ax : ax + dst_w] = to_atlas_pixels(shot)
        moved = continuity(small)
        print(f"  {name}.{anim}: {len(small)} frames, moves {' '.join(f'{m:.2f}' for m in moved)}" + ("  <- a jump" if max(moved) > rule.get("jump", 0.6) else ""))
        anims[anim] = {"row": r, "count": len(small), "fps": rule["fps"], "loop": rule.get("loop", False)}
        reel.append((anim, rule, small))
    path = save_atlas(name, atlas)
    print(f"  {path.relative_to(ROOT)}: {atlas.shape[1]}x{atlas.shape[0]}, {path.stat().st_size // 1024} KB, cell {dst_w}x{dst_h}")
    write_reels(name, spec, reel)
    rest = rows[0][2][0]
    return {
        "file": f"res://assets/art/{name}.png",
        "size": [atlas.shape[1], atlas.shape[0]],
        "cell": [dst_w, dst_h],
        "pad": PAD,
        "feet": [round((left + 3) * k, 2), round((up + 3) * k, 2)],
        "body_h": round((rest["bottom"] - rest["top"]) * k, 1),
        "world_h": spec.get("world_h", 1.0),
        "anims": anims,
    }


def gif_frame(shot: np.ndarray, tint: np.ndarray) -> Image.Image:
    rgb = np.clip(shot[..., :3] * tint, 0, 1)
    return Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB")


def save_gif(path: Path, shots: list[tuple[Image.Image, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pal = [s[0].convert("P", palette=Image.Palette.ADAPTIVE, colors=32) for s in shots]
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=[s[1] for s in shots], loop=0, optimize=True, disposal=2)


def write_reels(name: str, spec: dict, reel: list) -> None:
    tint = np.array([int(spec.get("tint", "#8fe8d8")[i : i + 2], 16) / 255.0 for i in (1, 3, 5)], dtype=np.float32)
    whole = []
    for anim, rule, small in reel:
        ms = int(1000 / rule["fps"])
        shots = [(gif_frame(s, tint), ms) for s in small]
        if not rule.get("loop", False):
            shots[-1] = (shots[-1][0], 700)
        save_gif(GIF_DIR / name / f"{anim}.gif", shots)
        whole += shots * (2 if rule.get("loop", False) else 1)
    save_gif(GIF_DIR / f"{name}.gif", whole)
    print(f"  docs/art/{name}.gif: {len(whole)} frames, {(GIF_DIR / f'{name}.gif').stat().st_size // 1024} KB")


def process(name: str, spec: dict) -> dict:
    cols, rows = spec["cols"], spec["rows"]
    frames: list[str] = spec["frames"]
    gray = load_gray(SOURCE / f"{name}.png")
    cells = cut_cells(gray, cols, rows)
    kept = []
    for i, frame in enumerate(frames):
        cell = cells[i]
        if cell.max() <= LINE_AT:
            raise SystemExit(f"{name}: cell {i + 1} ({frame}) is empty")
        closed = silhouette(cell)
        l, t, r, b = body_box(cell, closed)
        feet = (l + r) / 2.0, float(b) if spec.get("feet", "body") == "body" else (t + b) / 2.0
        ys, xs = np.nonzero(cell > 0.08)
        kept.append({"frame": frame, "cell": cell, "closed": closed, "feet": feet, "box": (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1), "body": (r - l, b - t)})
        share = float(closed.sum()) / float(max(1, (r - l) * (b - t)))
        print(f"  {name}.{frame}: body {r - l}x{b - t}, encloses {share:.0%}")
        if spec.get("closed", True) and share < 0.25 and frame != "stretch":
            print(f"  WARNING {name}.{frame}: its outline may be open, the inside shows through")
    left = max(k["feet"][0] - k["box"][0] for k in kept)
    right = max(k["box"][2] - k["feet"][0] for k in kept)
    up = max(k["feet"][1] - k["box"][1] for k in kept)
    down = max(k["box"][3] - k["feet"][1] for k in kept)
    src_w, src_h = int(np.ceil(left + right)) + 6, int(np.ceil(up + down)) + 6
    px = spec.get("cell_px", 256)
    k = px / max(src_w, src_h)
    dst_w, dst_h = max(4, round(src_w * k)), max(4, round(src_h * k))
    atlas = np.zeros(((dst_h + PAD) * rows + PAD, (dst_w + PAD) * cols + PAD, 4), dtype=np.float32)
    atlas[..., :3] = 1.0
    previews = {}
    bounds = {}
    for i, f in enumerate(kept):
        canvas = np.zeros((src_h, src_w, 4), dtype=np.float32)
        ox = int(round(left + 3 - f["feet"][0]))
        oy = int(round(up + 3 - f["feet"][1]))
        prem = rgba(f["cell"], f["closed"])
        x0, y0, x1, y1 = f["box"]
        x0, y0 = max(0, x0 - 2), max(0, y0 - 2)
        x1, y1 = min(prem.shape[1], x1 + 2), min(prem.shape[0], y1 + 2)
        tx0, ty0 = max(0, x0 + ox), max(0, y0 + oy)
        tx1, ty1 = min(src_w, x1 + ox), min(src_h, y1 + oy)
        canvas[ty0:ty1, tx0:tx1] = prem[ty0 - oy : ty1 - oy, tx0 - ox : tx1 - ox]
        small = fit(canvas, (dst_w, dst_h))
        previews[f["frame"]] = small
        # where the ink is in its cell, so a thing can stand on the floor whatever empty space its drawing has under it
        bx0, by0, bx1, by1 = f["box"]
        bounds[f["frame"]] = [round((bx0 + ox) * k, 1), round((by0 + oy) * k, 1), round((bx1 - bx0) * k, 1), round((by1 - by0) * k, 1)]
        ax = PAD + (i % cols) * (dst_w + PAD)
        ay = PAD + (i // cols) * (dst_h + PAD)
        atlas[ay : ay + dst_h, ax : ax + dst_w] = to_atlas_pixels(small)
    # below a stroke's edge the atlas stays white with no alpha; the gaps too
    path = save_atlas(name, atlas)
    size = atlas.shape[1], atlas.shape[0]
    body_h = next((f["body"][1] for f in kept if f["frame"] == spec.get("rest", frames[0])), kept[0]["body"][1]) * k
    print(f"  {path.relative_to(ROOT)}: {size[0]}x{size[1]}, {path.stat().st_size // 1024} KB, cell {dst_w}x{dst_h}")
    if "gif" in spec:
        write_gif(name, spec, previews)
    return {
        "file": f"res://assets/art/{name}.png",
        "size": list(size),
        "cols": cols,
        "rows": rows,
        "cell": [dst_w, dst_h],
        "pad": PAD,
        "feet": [(left + 3) * k, (up + 3) * k],
        "body_h": round(float(body_h), 1),
        "world_h": spec.get("world_h", 1.0),
        "frames": frames,
        "bounds": bounds,
    }


def process_plain(name: str, spec: dict) -> dict:
    """A whole picture with nothing to cut: 8-bit grey at the width the game wants."""
    image = Image.open(SOURCE / f"{name}.png").convert("L")
    height = round(image.height * spec["width"] / image.width)
    out = ROOT / "assets" / "art" / f"{name}.png"
    image.resize((spec["width"], height), Image.LANCZOS).save(out, optimize=True)
    print(f"  {out.relative_to(ROOT)}: {spec['width']}x{height}, {out.stat().st_size // 1024} KB")
    return {"file": f"res://assets/art/{name}.png", "size": [spec["width"], height]}


def write_gif(name: str, spec: dict, previews: dict) -> None:
    """A loop of the sheet's frames in its colour, on black."""
    GIF_DIR.mkdir(parents=True, exist_ok=True)
    tint = np.array([int(spec.get("tint", "#8fe8d8")[i : i + 2], 16) / 255.0 for i in (1, 3, 5)], dtype=np.float32)
    shots = []
    for frame, ms in spec["gif"]:
        p = previews[frame]
        rgb = np.clip(p[..., :3] * tint, 0, 1)
        h, w = rgb.shape[:2]
        big = Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").resize((w * 2 // 3 * 2, h * 2 // 3 * 2), Image.Resampling.LANCZOS)
        shots.append((big, ms))
    pal = [s[0].convert("P", palette=Image.Palette.ADAPTIVE, colors=48) for s in shots]
    out = GIF_DIR / f"{name}.gif"
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=[s[1] for s in shots], loop=0, optimize=True, disposal=2)
    print(f"  {out.relative_to(ROOT)}: {len(shots)} frames, {out.stat().st_size // 1024} KB")


def main() -> None:
    sheets = json.loads((HERE / "sheets.json").read_text())
    figure = sheets.pop("_figure")
    wanted = sys.argv[1:] or list(sheets)
    meta = json.loads(META.read_text()) if META.exists() else {}
    for name in wanted:
        spec = sheets[name]
        print(name)
        if spec.get("figure"):
            meta[name] = process_figure(name, {**figure, **spec})
            continue
        if not (SOURCE / f"{name}.png").exists():
            print(f"  skipped: no {SOURCE.relative_to(ROOT)}/{name}.png")
            continue
        meta[name] = process_plain(name, spec) if spec.get("plain") else process(name, spec)
    META.write_text(json.dumps(meta, indent=1) + "\n")
    print(f"{META.relative_to(ROOT)}: {len(meta)} sheets")


if __name__ == "__main__":
    main()
