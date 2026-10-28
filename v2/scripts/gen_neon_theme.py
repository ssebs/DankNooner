#!/usr/bin/env python3
"""Neon UI theme generator.

Renders 9-patch PNGs (vertical gradient fill, neon border, inner + outer glow) into
resources/themes/neon/, then writes two themes, each a copy of its classic base with the
StyleBoxFlats in its swaps replaced by StyleBoxTextures and its props set:
    DankNooner.tres -> DankNoonerNeon.tres  (menus; SWAPS, PROPS)
    hud.tres        -> hud_neon.tres        (riding HUD overlay; HUD_PROPS)
Content margins carry over and the glow sits in the expand margin, so each pair lays out
identically. Colors come from UtilsConstants' UI_* palette, shared with the game code.

Edit the bases or this script, never the generated themes (they're overwritten). Run from
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
THEME_DIR = ROOT / "resources/themes"
CONSTANTS = ROOT / "utils/constants.gd"
TEX_DIR = ROOT / "resources/themes/neon"
TEX_RES_DIR = "res://resources/themes/neon"
FONT_RES_DIR = "res://resources/fonts/MuseoModerno/static"
EMOJI_FONT = "res://resources/fonts/Noto_Color_Emoji/NotoColorEmoji-Regular.ttf"



def _palette() -> dict:
    """UtilsConstants' `const UI_X: Color = Color(r, g, b)` lines, by name."""
    found = re.findall(r"^const (UI_\w+): Color = Color\(([^)]*)\)", CONSTANTS.read_text(), re.M)
    return {name: tuple(float(c) for c in args.split(",")) for name, args in found}


PALETTE = _palette()
BLUE = PALETTE["UI_BLUE"]
ICE = PALETTE["UI_ICE"]
GOLD = PALETTE["UI_GOLD"]
GREEN = PALETTE["UI_GREEN"]
RED = PALETTE["UI_RED"]
GLASS = PALETTE["UI_GLASS"]
SKY = PALETTE["UI_SKY"]
WHITE = (1.0, 1.0, 1.0)

PANEL_RADII = (16, 16, 16, 4)  # tl, tr, br, bl — every corner rounded but the bottom left
ROW_RADII = (10, 10, 10, 3)
CHIP_RADII = (12, 12, 12, 4)
BACKDROP_RADII = (24, 24, 24, 6)
CLEAR = (0, 0, 0, 0)
CENTRE = 8  # px; the stretched middle of each 9-patch
FADE = 96  # px; how far a faded side ramps to transparent
HEAVY = 1  # px; extra border on the side facing away from a fade


@dataclass
class Box:
    radii: tuple = PANEL_RADII
    border: int = 2
    fill_top: tuple = CLEAR
    fill_bot: tuple = CLEAR
    border_color: tuple = CLEAR
    glow_color: tuple = CLEAR
    glow: int = 0
    fade: str = ""  # a SIDES entry: that side has no edge and ramps to transparent
    fade_px: int = FADE

    def margin(self) -> int:
        return self.glow + max(self.radii) + self.border + 2

    def side_margin(self, side: str) -> int:
        return self.fade_px if side == self.fade else self.margin()


@dataclass
class Look:
    """A palette. Every box derives from these few colors, so the screens can't drift."""
    top: tuple  # panel fill gradient
    bot: tuple
    edge: tuple  # resting border + glow
    hot: tuple  # hover / pressed / primary
    hot_border: tuple
    focus: tuple
    border: int
    alpha: float  # panel fill opacity
    rest_glow: float  # resting glow strength; 0 = glow only on hover / focus / press


def _mix(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def _boxes(k: Look) -> dict:
    """name -> Box. Names become resources/themes/neon/<name>.png."""
    def fill(top, bot, a):
        return dict(fill_top=(*top, a), fill_bot=(*bot, a))

    def lit(rgb, strength, px, border_rgb=None):
        return dict(
            border_color=(*(border_rgb or rgb), 1.0),
            glow_color=(*rgb, strength), glow=round(px) if strength > 0 else 0,
        )

    b = k.border
    # Edges at rest are present but unlit, so only what you act on is bright.
    dim = _mix(k.bot, k.edge, 0.55)
    rest = lit(k.edge, 0.5 * k.rest_glow, 14, dim)
    panel = fill(k.top, k.bot, k.alpha)
    button = fill(_mix(k.top, k.hot, 0.08), k.bot, 1.0)
    hover = {**fill(_mix(k.top, k.hot, 0.3), _mix(k.bot, k.hot, 0.1), 1.0), **lit(k.hot, 0.75, 14, k.hot_border)}
    pressed = {**fill(k.hot, _mix(k.hot, k.bot, 0.45), 1.0), **lit(k.hot, 0.9, 16, k.hot_border)}
    focus = lit(k.focus, 0.7, 12)
    disabled = dict(fill_top=(0.12, 0.12, 0.16, 1), fill_bot=(0.06, 0.06, 0.09, 1), border_color=(0.28, 0.3, 0.4, 1))
    dark = fill(SKY, SKY, 0.95)
    return {
        "panel": Box(border=b, **panel, **rest),
        "backdrop": Box(BACKDROP_RADII, b, **fill(k.top, k.bot, k.alpha - 0.05), **lit(k.edge, 0.3 * k.rest_glow, 18, dim)),
        "btn_normal": Box(border=b, **button, **lit(k.edge, 0.3 * k.rest_glow, 10, dim)),
        "btn_hover": Box(border=b, **hover),
        "btn_pressed": Box(border=b, **pressed),
        "btn_focus": Box(border=b + 1, **focus),
        "btn_disabled": Box(border=b, **disabled),
        "btn_primary": Box(border=b, **fill(_mix(k.top, k.hot, 0.6), _mix(k.bot, k.hot, 0.25), 1.0), **lit(k.hot, 0.7, 16, k.hot_border)),
        # BoostCell is 20px across either way, its fill 12px: margins must fit inside those.
        "boost_track": Box((6, 6, 6, 2), 2, **fill(GLASS, GLASS, 0.85), **lit(k.edge, 0.45, 8)),
        # White, so BoostGauge can tint it through modulate_color.
        "boost_fill": Box((4, 4, 4, 1), 0, **fill(WHITE, WHITE, 1.0)),
        "input": Box(border=b, **dark, **lit(k.edge, 0.2 * k.rest_glow, 8, dim)),
        "input_focus": Box(border=b, **dark, **lit(k.edge, 0.7, 12)),
        "chip": Box(CHIP_RADII, b, **fill(k.top, k.bot, 0.95), **lit(k.edge, 0.35 * k.rest_glow, 8, dim)),
        "row_panel": Box(border=b, **fill(k.top, k.bot, 0.9), **lit(k.edge, 0.2 * k.rest_glow, 8, dim)),
        "row_normal": Box(ROW_RADII, b, **button, **lit(k.edge, 0.25 * k.rest_glow, 6, dim)),
        "row_hover": Box(ROW_RADII, b, **hover),
        "row_hover_pressed": Box(ROW_RADII, b, **fill(_mix(k.hot, WHITE, 0.35), k.hot, 1.0), **lit(k.hot, 0.8, 10, k.hot_border)),
        "row_pressed": Box(ROW_RADII, b, **pressed),
        "row_focus": Box(ROW_RADII, b, **lit(k.focus, 0.6, 8)),
        "feed": Box(ROW_RADII, b, **fill(k.top, k.bot, 0.7), **lit(k.edge, 0.3 * k.rest_glow, 8, _mix(k.bot, k.edge, 0.7))),
        **{f"fade_{side}": Box(border=b, **panel, **rest, fade=side) for side in SIDES},
    }


def _font(weight: str) -> str:
    """A MuseoModerno weight that keeps the emoji fallback; build_theme adds the resources."""
    return f'SubResource("Font_{weight}")'


# Menus: clean glass — hairline borders, light only where you act.
MENU = Look(
    top=GLASS, bot=GLASS, edge=BLUE, hot=BLUE, hot_border=ICE,
    focus=ICE, border=1, alpha=0.75, rest_glow=0.0,
)
# Flat text, like the logo: callouts / +points, and your own leaderboard row in blue. In both
# themes, as the results screen and garage pops only get the menu theme.
FLAT_PROPS = {
    "PopupLabel/base_type": '&"Label"',
    "PopupLabel/font_sizes/font_size": 36,
    "OwnLabel/base_type": '&"Label"',
    "OwnLabel/colors/font_color": (*BLUE, 1),
}

# Set on top of DankNooner.tres's [resource]: a drop shadow for legibility over the world, dark
# text on the solid pressed fill (a checked CheckBox keeps its normal box, so not there).
PROPS = {
    "Label/colors/font_shadow_color": (0, 0, 0, 0.6),
    "Label/constants/shadow_offset_x": 0,
    "Label/constants/shadow_offset_y": 2,
    # Titles are neon signs: ice-white core, thin blue tube, faint halo (the shadow's outline).
    "TitleLabel/colors/font_color": (0.92, 0.98, 1, 1),
    "TitleLabel/constants/outline_size": 3,
    "TitleLabel/colors/font_shadow_color": (*BLUE, 0.3),
    "TitleLabel/constants/shadow_offset_y": 0,
    "TitleLabel/constants/shadow_outline_size": 16,
    "Button/colors/font_pressed_color": (*MENU.bot, 1),
    "Button/colors/font_hover_pressed_color": (*MENU.bot, 1),
    "TabButton/colors/font_pressed_color": (1, 1, 1, 1),
    "TabButton/colors/font_hover_pressed_color": (1, 1, 1, 1),
    "CheckBox/colors/font_pressed_color": (1, 1, 1, 1),
    "CheckBox/colors/font_hover_pressed_color": (1, 1, 1, 1),
    "Heading1Label/fonts/font": _font("Bold"),
    "TableHeaderLabel/fonts/font": _font("Bold"),
    "TableHeaderLabel/colors/font_color": (*BLUE, 1),
    **FLAT_PROPS,
    "MoneyLabel/base_type": '&"Label"',
    "MoneyLabel/colors/font_color": (*GREEN, 1),
    "MoneyLabel/colors/font_outline_color": (*GLASS, 1),
    "MoneyLabel/constants/outline_size": 4,
    "NameTagLabel/colors/font_color": (*GREEN, 1),
    "PingLabel/colors/font_color": (*GREEN, 1),
    **{f"DangerButton/colors/{c}": (*RED, 1) for c in (
        "font_color", "font_focus_color", "font_hover_color", "font_hover_pressed_color", "font_pressed_color"
    )},
}

# DankNooner.tres StyleBox id -> _boxes() name. Ids missing here (empty spacers, the avatar ring,
# the underline tabs) stay as they are.
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
    "StyleBoxFlat_garagerowsel": "btn_hover",
    "StyleBoxFlat_feedpanel": "feed",
    "StyleBoxFlat_fadeleft": "fade_left",
    "StyleBoxFlat_fadetop": "fade_top",
    "StyleBoxFlat_faderight": "fade_right",
    "StyleBoxFlat_fadebottom": "fade_bottom",
    "StyleBoxFlat_tabpad": "panel",
    "StyleBoxFlat_boostfill": "boost_fill",
}
# External StyleBox files the base theme references: ext id -> _boxes() name.
EXT_SWAPS = {"1_bvbyg": "btn_normal", "5_object": "boost_track"}

def _outlined(theme_type: str, size: int) -> dict:
    """The dark outline, and a hard drop of the outlined glyph under it."""
    return {
        f"{theme_type}/colors/font_outline_color": (*GLASS, 1),
        f"{theme_type}/constants/outline_size": size,
        f"{theme_type}/colors/font_shadow_color": (*GLASS, 0.8),
        f"{theme_type}/constants/shadow_offset_x": 0,
        f"{theme_type}/constants/shadow_offset_y": size // 2,
        f"{theme_type}/constants/shadow_outline_size": size,
    }


# Values: speed, scores, names, money. The closest theme wins per item, so each needs its own font
# here or it gets hud_neon's Label font.
TITLE_TYPES = ("HUDTitleLabel", "MoneyLabel", "XPLabel", "OwnLabel", "PopupLabel")

# hud_neon.tres overlays the riding HUD: Main (Medium) for words, Title (SemiBold) for values, and
# one dark outline on every text so white can't blend into the world's neon.
HUD_PROPS = {
    "Label/fonts/font": _font("Medium"),
    "Label/font_sizes/font_size": 20,
    **_outlined("Label", 6),
    "RichTextLabel/fonts/normal_font": _font("Medium"),
    "RichTextLabel/fonts/bold_font": _font("SemiBold"),
    **_outlined("RichTextLabel", 6),
    "HUDTitleLabel/base_type": '&"Label"',
    **{f"{t}/fonts/font": _font("SemiBold") for t in TITLE_TYPES},
    # 48 / 80
    "HUDHeroLabel/base_type": '&"HUDTitleLabel"',
    **_outlined("HUDHeroLabel", 10),
    "DimLabel/base_type": '&"Label"',
    "DimLabel/colors/font_color": (1, 1, 1, 0.6),
    "XPLabel/colors/font_color": (*GOLD, 1),
    "WarningLabel/colors/font_color": (*RED, 1),
    **FLAT_PROPS,
}

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
    w = box.side_margin("left") + CENTRE + box.side_margin("right")
    h = box.side_margin("top") + CENTRE + box.side_margin("bottom")
    hw, hh = w / 2.0 - box.glow, h / 2.0 - box.glow
    inner_px = box.border + 6
    pixels = bytearray()
    for y in range(h):
        pixels.append(0)  # PNG filter: none
        t = _clamp01((y + 0.5 - box.glow) / (h - 2 * box.glow))
        fill = _mix(box.fill_top, box.fill_bot, t)
        for x in range(w):
            sx, sy = x + 0.5 - w / 2.0, y + 0.5 - h / 2.0
            # The faded half samples the middle, so its borders run straight out under the ramp.
            if box.fade == "left":
                sx = max(sx, 0.0)
            elif box.fade == "right":
                sx = min(sx, 0.0)
            elif box.fade == "top":
                sy = max(sy, 0.0)
            elif box.fade == "bottom":
                sy = min(sy, 0.0)
            d = _sdf(sx, sy, hw, hh, box.radii)
            inside = _clamp01(0.5 - d)
            px = [0.0, 0.0, 0.0, 0.0]
            if box.glow > 0 and d > 0.0:
                falloff = _clamp01(1.0 - d / box.glow) ** 2
                _over(px, box.glow_color[:3], box.glow_color[3] * falloff * (1.0 - inside))
            _over(px, fill[:3], fill[3] * inside)
            # Inner edge of the border; the side facing away from a fade is drawn heavier.
            d_in = d + box.border
            if box.fade:
                away, half = {"left": (sx, hw), "right": (-sx, hw), "top": (sy, hh), "bottom": (-sy, hh)}[box.fade]
                d_in = max(d_in, away - (half - box.border - HEAVY))
            # Inner glow: the border's light bleeding inward, like a neon tube.
            if d < 0.0:
                inner = _clamp01(1.0 - -d_in / inner_px) ** 2
                _over(px, box.border_color[:3], box.glow_color[3] * 0.4 * inner * inside)
            ring = inside * _clamp01(d_in + 0.5)
            _over(px, box.border_color[:3], box.border_color[3] * ring)
            if box.fade:
                into = {"left": x, "right": w - 1 - x, "top": y, "bottom": h - 1 - y}[box.fade]
                px[3] *= _clamp01((into + 0.5) / box.fade_px)
            pixels += bytes(round(_clamp01(c) * 255) for c in px)
    return w, h, bytes(pixels)


def write_png(path: Path, w: int, h: int, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    header = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
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


def _value(v) -> str:
    """A .tres literal: tuples are Colors, everything else is written as-is."""
    if isinstance(v, tuple):
        return "Color(%s)" % ", ".join(f"{c:g}" for c in v)
    return str(v)


def _fonts(props: dict) -> tuple:
    """(ext lines, sub resources) for every _font() weight the props name."""
    weights = sorted(set(re.findall(r'SubResource\("Font_(\w+)"\)', " ".join(map(str, props.values())))))
    if not weights:
        return "", ""
    ext = f'[ext_resource type="FontFile" path="{EMOJI_FONT}" id="font_emoji"]\n'
    subs = ""
    for w in weights:
        ext += f'[ext_resource type="FontFile" path="{FONT_RES_DIR}/MuseoModerno-{w}.ttf" id="font_{w}"]\n'
        subs += (
            f'[sub_resource type="FontVariation" id="Font_{w}"]\n'
            f'fallbacks = Array[Font]([ExtResource("font_emoji")])\n'
            f'base_font = ExtResource("font_{w}")\n\n'
        )
    return ext, subs


def _set_props(text: str, props: dict) -> str:
    """Replace or append each prop line in the [resource] section."""
    head, res = text.split("\n[resource]\n")
    for key, value in props.items():
        line = f"{key} = {_value(value)}"
        res, n = re.subn(rf"^{re.escape(key)} = .*$", lambda _: line, res, flags=re.M)
        if n == 0:
            res = res.rstrip("\n") + "\n" + line + "\n"
    return head + "\n[resource]\n" + res


def _texture_box(sub_id: str, box: Box, name: str, props: dict) -> str:
    """A StyleBoxTexture that lays out like the flat box it replaces."""
    lines = [f'[sub_resource type="StyleBoxTexture" id="{sub_id}"]']
    for side in SIDES:
        # A flat box with no content margin falls back to its border width; a texture box
        # would fall back to its (much larger) texture margin, so spell it out.
        content = props.get(f"content_margin_{side}", props.get(f"border_width_{side}", "0"))
        lines.append(f"content_margin_{side} = {float(content)}")
    lines.append(f'texture = ExtResource("neon_{name}")')
    for side in SIDES:
        lines.append(f"texture_margin_{side} = {float(box.side_margin(side))}")
    for side in SIDES:
        # No glow past a faded side, so its ramp starts at the box edge.
        expand = float(props.get(f"expand_margin_{side}", "0")) + (0 if side == box.fade else box.glow)
        lines.append(f"expand_margin_{side} = {expand}")
    return "\n".join(lines) + "\n"


def build_theme(
    base: str, out: str, swaps: dict, ext_swaps: dict, props: dict, boxes: dict
) -> set:
    """Write THEME_DIR/out from THEME_DIR/base; returns the box names it uses."""
    text = (THEME_DIR / base).read_text()
    used = set()

    def swap_sub(match: re.Match) -> str:
        sub_id, body = match.group(1), match.group(2)
        if sub_id not in swaps:
            return match.group(0)
        used.add(swaps[sub_id])
        return _texture_box(sub_id, boxes[swaps[sub_id]], swaps[sub_id], _props(body)) + "\n"

    text = re.sub(
        r'\[sub_resource type="StyleBoxFlat" id="([^"]+)"\]\n((?:[^\[\n].*\n)*)\n', swap_sub, text
    )

    font_ext, new_subs = _fonts(props)
    for ext_id, name in ext_swaps.items():
        ext_line = re.search(r'\[ext_resource [^\n]*path="([^"]+)" id="%s"\]\n' % ext_id, text)
        source = (ROOT / ext_line.group(1).removeprefix("res://")).read_text()
        sub_id = f"StyleBoxTexture_{name}"
        new_subs += _texture_box(sub_id, boxes[name], name, _props(source)) + "\n"
        text = text.replace(ext_line.group(0), "")
        text = text.replace(f'ExtResource("{ext_id}")', f'SubResource("{sub_id}")')
        used.add(name)

    ext_lines = "".join(
        f'[ext_resource type="Texture2D" path="{TEX_RES_DIR}/{name}.png" id="neon_{name}"]\n'
        for name in sorted(used)
    ) + font_ext
    first_sub = text.index("[sub_resource")
    text = text[:first_sub].rstrip("\n") + "\n" + ext_lines + "\n" + new_subs + text[first_sub:]
    text = _set_props(text, props)
    # Its own resource — drop the base theme's uid.
    text = re.sub(r'^\[gd_resource type="Theme" format=3 uid="[^"]+"\]', '[gd_resource type="Theme" format=3]', text)
    (THEME_DIR / out).write_text(text, newline="\n")
    return used


#endregion


def main() -> None:
    boxes = _boxes(MENU)
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    used = build_theme("DankNooner.tres", "DankNoonerNeon.tres", SWAPS, EXT_SWAPS, PROPS, boxes)
    used |= build_theme("hud.tres", "hud_neon.tres", {}, {}, HUD_PROPS, boxes)
    for name in sorted(used):
        write_png(TEX_DIR / f"{name}.png", *render(boxes[name]))
    print(f"wrote DankNoonerNeon.tres + hud_neon.tres + {len(used)} textures in {TEX_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
