@tool
## Semantic status colors (OK / WARN / ERR) shared by UI + in-world feedback.
## Static-only — never instanced. Mirrors MaterialPresets' enum + lookup pattern.
class_name SemanticColors

enum Value { OK, WARN, ERR }

const COLOR_VALUES: Dictionary = {
	Value.OK: UtilsConstants.UI_BLUE,
	Value.WARN: UtilsConstants.UI_GOLD,
	Value.ERR: UtilsConstants.UI_RED,
}
