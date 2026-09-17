@tool
## Semantic status colors (OK / WARN / ERR) shared by UI + in-world feedback.
## Static-only — never instanced. Mirrors MaterialPresets' enum + lookup pattern.
class_name SemanticColors

enum Value { OK, WARN, ERR }

const COLOR_VALUES: Dictionary = {
	Value.OK: Color(0.25490198, 0.6862745, 1.0),
	Value.WARN: Color(1.0, 0.85, 0.2),
	Value.ERR: Color(1.0, 0.24, 0.19),
}
