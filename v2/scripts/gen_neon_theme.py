#!/usr/bin/env python3
"""Neon UI theme generator.

Renders 9-patch PNGs (vertical gradient fill, neon border, inner + outer glow) into
resources/themes/neon/, then writes resources/themes/DankNoonerNeon.tres: a copy of
DankNooner.tres with the StyleBoxFlats listed in SWAPS replaced by StyleBoxTextures. Content
margins carry over and the glow sits in the expand margin, so both themes lay out identically.

Edit DankNooner.tres or this script, never DankNoonerNeon.tres (it's overwritten). Run from
anywhere, standard library only:
    python3 scripts/gen_neon_theme.py
"""

import math
import re
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE_THEME = ROOT / "resources/themes/DankNooner.tres"
OUT_THEME = ROOT / "resources/themes/DankNoonerNeon.tres"
TEX_DIR = ROOT / "resources/themes/neon"
TEX_RES_DIR = "res://resources/themes/neon"

# Same blue as neon_edges.gdshader's edge_color, so the HUD matches the world.
BLUE = (0.255, 0.686, 1.0)
GREEN = (0.255, 0.686, 0.278)
NAVY_TOP = (0.09, 0.06, 0.20)
NAVY_BOT = (0.02, 0.03, 0.08)
PANEL_RADII = (16, 4, 16, 4)  # tl, tr, br, bl — the house slanted corners
ROW_RADII = (10, 3, 10, 3)


@dataclass
class Box:
    radii: tuple = PANEL_RADII
    border: int = 3
    fill_top: tuple = (*NAVY_TOP, 0.85)
    fill_bot: tuple = (*NAVY_BOT, 0.85)
    border_color: tuple = (*BLUE, 1.0)
    glow_color: tuple = (*BLUE, 0.55)
    glow: int = 14

    def margin(self) -> int:
        return self.glow + max(self.radii) + self.border + 2


def rgba(rgb: tuple, a: float) -> tuple:
    return (*rgb, a)


# name -> look. Names become resources/themes/neon/<name>.png.
BOXES = {
    "panel": Box(),
    "backdrop": Box(
        radii=(24, 6, 24, 6), border=2,
        fill_top=(0.05, 0.03, 0.12, 0.82), fill_bot=(0.01, 0.01, 0.04, 0.82),
        border_color=rgba(BLUE, 0.6), glow_color=rgba(BLUE, 0.35), glow=18,
    ),
    "outline": Box(fill_top=(0, 0, 0, 0), fill_bot=(0, 0, 0, 0)),
    "btn_normal": Box(
        fill_top=(0.05, 0.20, 0.36, 1), fill_bot=(0.01, 0.07, 0.15, 1),
        glow_color=rgba(BLUE, 0.3), glow=10,
    ),
    "btn_hover": Box(
        fill_top=(0.10, 0.36, 0.60, 1), fill_bot=(0.03, 0.15, 0.30, 1),
        border_color=(0.65, 0.9, 1, 1), glow_color=rgba(BLUE, 0.75),
    ),
    "btn_pressed": Box(
        fill_top=(*BLUE, 1), fill_bot=(0.08, 0.38, 0.70, 1),
        border_color=(0.8, 0.95, 1, 1), glow_color=rgba(BLUE, 0.9), glow=16,
    ),
    "btn_focus": Box(
        fill_top=(0, 0, 0, 0), fill_bot=(0, 0, 0, 0),
        border_color=rgba(GREEN, 1), glow_color=rgba(GREEN, 0.7), glow=12,
    ),
    "btn_disabled": Box(
        fill_top=(0.14, 0.14, 0.17, 1), fill_bot=(0.07, 0.07, 0.09, 1),
        border_color=(0.3, 0.3, 0.36, 1), glow_color=(0, 0, 0, 0), glow=0,
    ),
    "btn_primary": Box(
        fill_top=(0.12, 0.52, 0.88, 1), fill_bot=(0.02, 0.20, 0.42, 1),
        border_color=(0.7, 0.92, 1, 1), glow_color=rgba(BLUE, 0.7), glow=16,
    ),
    "input": Box(
        fill_top=(0.02, 0.03, 0.08, 0.95), fill_bot=(0.02, 0.03, 0.08, 0.95),
        border_color=rgba(BLUE, 0.6), glow_color=rgba(BLUE, 0.2), glow=8,
    ),
    "input_focus": Box(
        fill_top=(0.02, 0.03, 0.08, 0.95), fill_bot=(0.02, 0.03, 0.08, 0.95),
        glow_color=rgba(BLUE, 0.7), glow=12,
    ),
    "chip": Box(
        radii=(12, 4, 12, 4), border=2,
        fill_top=(*NAVY_TOP, 0.95), fill_bot=(*NAVY_BOT, 0.95),
        glow_color=rgba(BLUE, 0.35), glow=8,
    ),
    "row_panel": Box(
        border=2, fill_top=(*NAVY_TOP, 0.9), fill_bot=(*NAVY_BOT, 0.9),
        border_color=rgba(BLUE, 0.45), glow_color=rgba(BLUE, 0.2), glow=8,
    ),
    "row_normal": Box(
        radii=ROW_RADII, border=2,
        fill_top=(0.02, 0.20, 0.36, 1), fill_bot=(0.0, 0.10, 0.20, 1),
        glow_color=rgba(BLUE, 0.25), glow=6,
    ),
    "row_hover": Box(
        radii=ROW_RADII, border=2,
        fill_top=(0.10, 0.45, 0.72, 1), fill_bot=(0.04, 0.22, 0.40, 1),
        border_color=(0.65, 0.9, 1, 1), glow_color=rgba(BLUE, 0.6), glow=10,
    ),
    "row_hover_pressed": Box(
        radii=ROW_RADII, border=2,
        fill_top=(0.5, 0.82, 1, 1), fill_bot=(0.25, 0.6, 0.95, 1),
        border_color=(0.8, 0.95, 1, 1), glow_color=rgba(BLUE, 0.8), glow=10,
    ),
    "row_pressed": Box(
        radii=ROW_RADII, border=2,
        fill_top=(*BLUE, 1), fill_bot=(0.1, 0.45, 0.8, 1),
        border_color=(0.7, 0.92, 1, 1), glow_color=rgba(BLUE, 0.7), glow=10,
    ),
    "row_focus": Box(
        radii=ROW_RADII, border=2, fill_top=(0, 0, 0, 0), fill_bot=(0, 0, 0, 0),
        border_color=rgba(GREEN, 1), glow_color=rgba(GREEN, 0.6), glow=8,
    ),
    "tab_sel": Box(
        radii=(12, 4, 0, 0), border=2,
        fill_top=(*NAVY_TOP, 1), fill_bot=(*NAVY_BOT, 1),
        glow_color=rgba(BLUE, 0.5), glow=10,
    ),
    "tab_hover": Box(
        radii=(12, 4, 0, 0), border=2,
        border_color=rgba(BLUE, 0.5), glow_color=rgba(BLUE, 0.2), glow=8,
    ),
    "tab_unsel": Box(
        radii=(12, 4, 0, 0), border=2,
        fill_top=(0.03, 0.03, 0.08, 0.6), fill_bot=(0.03, 0.03, 0.08, 0.6),
        border_color=(0, 0, 0, 0), glow_color=(0, 0, 0, 0), glow=0,
    ),
    "tab_profile": Box(
        radii=(12, 4, 0, 0), border=2,
        fill_top=(*NAVY_TOP, 1), fill_bot=(*NAVY_BOT, 1),
        glow_color=rgba(BLUE, 0.35), glow=8,
    ),
    "feed": Box(
        radii=ROW_RADII, border=2,
        fill_top=(*NAVY_TOP, 0.7), fill_bot=(*NAVY_BOT, 0.7),
        border_color=rgba(BLUE, 0.7), glow_color=rgba(BLUE, 0.3), glow=8,
    ),
}

# DankNooner.tres StyleBox id -> BOXES name. Ids missing here (empty spacers, the avatar ring)
# stay as they are.
SWAPS = {
    "StyleBoxFlat_vtut7": "btn_disabled",
    "StyleBoxFlat_bvbyg": "btn_focus",
    "StyleBoxFlat_hydtf": "btn_hover",
    "StyleBoxFlat_yn56u": "btn_hover",
    "StyleBoxFlat_7depn": "btn_pressed",
    "StyleBoxFlat_4v18w": "btn_primary",
    "StyleBoxFlat_hudpanel": "panel",
    "StyleBoxFlat_menupanel": "panel",
    "StyleBoxFlat_6tpw2": "panel",
    "StyleBoxFlat_backdrop": "backdrop",
    "StyleBoxFlat_outline": "outline",
    "StyleBoxFlat_gbla1": "input",
    "StyleBoxFlat_wtkwa": "input_focus",
    "StyleBoxFlat_iu7fo": "input",
    "StyleBoxFlat_k75rx": "btn_pressed",
    "StyleBoxFlat_trkchip": "chip",
    "StyleBoxFlat_trkrow": "row_panel",
    "StyleBoxFlat_rowbtn": "row_normal",
    "StyleBoxFlat_rowbtnhover": "row_hover",
    "StyleBoxFlat_rowbtnhoverpressed": "row_hover_pressed",
    "StyleBoxFlat_rowbtnpressed": "row_pressed",
    "StyleBoxFlat_rowbtnfocus": "row_focus",
    "StyleBoxFlat_tabsel": "tab_sel",
    "StyleBoxFlat_tabhover": "tab_hover",
    "StyleBoxFlat_tabunsel": "tab_unsel",
    "StyleBoxFlat_profiletab": "tab_profile",
    "StyleBoxFlat_garagerowsel": "btn_hover",
    "StyleBoxFlat_feedpanel": "feed",
}
# External StyleBox files the base theme references: ext id -> BOXES name.
EXT_SWAPS = {"1_bvbyg": "btn_normal"}

SIDES = ("left", "top", "right", "bottom")


#region rendering


def _sdf(px: float, py: float, hw: float, hh: float, radii: tuple) -> float:
    """Signed distance to a rounded box centred on the origin, one radius per corner."""
    tl, tr, br, bl = radii
    if py < 0:
        r = tl if px < 0 else tr
    else:
        r = bl if px < 0 else br
    qx = abs(px) - (hw - r)
    qy = abs(py) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def _over(dst: list, rgb: tuple, a: float) -> None:
    """Straight-alpha source-over, in place."""
    if a <= 0.0:
        return
    out_a = a + dst[3] * (1.0 - a)
    for i in range(3):
        dst[i] = (rgb[i] * a + dst[i] * dst[3] * (1.0 - a)) / out_a
    dst[3] = out_a


def _clamp01(v: float) -> float:
    return min(max(v, 0.0), 1.0)


def render(box: Box) -> tuple:
    m = box.margin()
    size = 2 * m + 4
    hw = hh = size / 2.0 - box.glow
    inner_px = box.border + 6
    pixels = bytearray()
    for y in range(size):
        pixels.append(0)  # PNG filter: none
        t = _clamp01((y + 0.5 - box.glow) / (size - 2 * box.glow))
        fill = [box.fill_top[i] + (box.fill_bot[i] - box.fill_top[i]) * t for i in range(4)]
        for x in range(size):
            d = _sdf(x + 0.5 - size / 2.0, y + 0.5 - size / 2.0, hw, hh, box.radii)
            inside = _clamp01(0.5 - d)
            px = [0.0, 0.0, 0.0, 0.0]
            if box.glow > 0 and d > 0.0:
                falloff = _clamp01(1.0 - d / box.glow) ** 2
                _over(px, box.glow_color[:3], box.glow_color[3] * falloff * (1.0 - inside))
            _over(px, fill[:3], fill[3] * inside)
            # Inner glow: the border's light bleeding inward, like a neon tube.
            if d < 0.0:
                inner = _clamp01(1.0 - (-d - box.border) / inner_px) ** 2
                _over(px, box.border_color[:3], box.glow_color[3] * 0.4 * inner * inside)
            ring = inside * _clamp01(d + box.border + 0.5)
            _over(px, box.border_color[:3], box.border_color[3] * ring)
            pixels += bytes(round(_clamp01(c) * 255) for c in px)
    return size, bytes(pixels)


def write_png(path: Path, size: int, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


#endregion


#region theme


def _props(block: str) -> dict:
    return dict(re.findall(r"^(\w+) = (.+)$", block, re.M))


def _texture_box(sub_id: str, name: str, props: dict) -> str:
    """A StyleBoxTexture that lays out like the flat box it replaces."""
    box = BOXES[name]
    lines = [f'[sub_resource type="StyleBoxTexture" id="{sub_id}"]']
    for side in SIDES:
        # A flat box with no content margin falls back to its border width; a texture box
        # would fall back to its (much larger) texture margin, so spell it out.
        content = props.get(f"content_margin_{side}", props.get(f"border_width_{side}", "0"))
        lines.append(f"content_margin_{side} = {float(content)}")
    lines.append(f'texture = ExtResource("neon_{name}")')
    for side in SIDES:
        lines.append(f"texture_margin_{side} = {float(box.margin())}")
    for side in SIDES:
        expand = float(props.get(f"expand_margin_{side}", "0")) + box.glow
        lines.append(f"expand_margin_{side} = {expand}")
    return "\n".join(lines) + "\n"


def build_theme() -> set:
    text = BASE_THEME.read_text()
    used = set()

    def swap_sub(match: re.Match) -> str:
        sub_id, body = match.group(1), match.group(2)
        if sub_id not in SWAPS:
            return match.group(0)
        used.add(SWAPS[sub_id])
        return _texture_box(sub_id, SWAPS[sub_id], _props(body)) + "\n"

    text = re.sub(
        r'\[sub_resource type="StyleBoxFlat" id="([^"]+)"\]\n((?:[^\[\n].*\n)*)\n', swap_sub, text
    )

    new_subs = ""
    for ext_id, name in EXT_SWAPS.items():
        ext_line = re.search(r'\[ext_resource [^\n]*path="([^"]+)" id="%s"\]\n' % ext_id, text)
        source = (ROOT / ext_line.group(1).removeprefix("res://")).read_text()
        sub_id = f"StyleBoxTexture_{name}"
        new_subs += _texture_box(sub_id, name, _props(source)) + "\n"
        text = text.replace(ext_line.group(0), "")
        text = text.replace(f'ExtResource("{ext_id}")', f'SubResource("{sub_id}")')
        used.add(name)

    ext_lines = "".join(
        f'[ext_resource type="Texture2D" path="{TEX_RES_DIR}/{name}.png" id="neon_{name}"]\n'
        for name in sorted(used)
    )
    first_sub = text.index("[sub_resource")
    text = text[:first_sub].rstrip("\n") + "\n" + ext_lines + "\n" + new_subs + text[first_sub:]
    # Its own resource — drop the base theme's uid.
    text = re.sub(r'^\[gd_resource type="Theme" format=3 uid="[^"]+"\]', '[gd_resource type="Theme" format=3]', text)
    OUT_THEME.write_text(text)
    return used


#endregion


def main() -> None:
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    used = build_theme()
    for name in sorted(used):
        size, raw = render(BOXES[name])
        write_png(TEX_DIR / f"{name}.png", size, raw)
    print(f"wrote {OUT_THEME.relative_to(ROOT)} + {len(used)} textures in {TEX_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
