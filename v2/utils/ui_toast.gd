# UIToast
extends Node

enum ToastLevel { NORMAL, WARN, ERR }

var color_map: Dictionary[ToastLevel, Dictionary] = {
    # White on Gray
    ToastLevel.NORMAL:
    {
        "bgcolor": Color(0.5, 0.5, 0.5, 0.7),  # Background Color
        "color": Color(1, 1, 1, 1),  # Text Color
    },
    # Dark Yellow on Yellow
    ToastLevel.WARN:
    {
        "bgcolor": Color(0.3, 0.25, 0.0, 0.85),  # Background Color (dark yellow/amber)
        "color": Color(1.0, 0.9, 0.4, 1),  # Text Color (bright yellow)
    },
    # White on Red
    ToastLevel.ERR:
    {
        "bgcolor": Color(0.5, 0.0, 0.0, 0.85),  # Background Color (dark red)
        "color": Color(1, 1, 1, 1),  # Text Color (white)
    }
}


func ShowToast(msg: String, level: ToastLevel = ToastLevel.NORMAL, duration: int = 2):
    var colors = color_map[level]
    ToastPartyLib.show(
        {
            "text": msg,
            "bgcolor": colors["bgcolor"],
            "color": colors["color"],
            "gravity": "bottom",
            "direction": "right",
            "text_size": 24,
            "duration": duration
            # "use_font": true
        }
    )

# OG config obj for reference
# {
#     "text": "🥑Some Text🥑",           # Text (emojis can be used)
#     "bgcolor": Color(0, 0, 0, 0.7),     # Background Color
#     "color": Color(1, 1, 1, 1),         # Text Color
#     "gravity": "top",                   # top or bottom
#     "direction": "right",               # left or center or right
#     "text_size": 18,                    # [optional] Text (font) size // experimental
#     "use_font": true                    # [optional] Use custom ToastParty font // experimental
# }
