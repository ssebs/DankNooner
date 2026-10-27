@tool
## Kill-feed style log of every rider's banked combos and bails, newest on top and right-aligned
## under the leaderboard. Each line fades out after HOLD_SECS. Fed by RidingHUDState from the
## server's TrickManager.
class_name TrickFeed extends VBoxContainer

@export var font_size: int = 20
## Rider names and points — heavier than the theme font so they read apart from the trick names.
@export var bold_font: Font

const MAX_LINES: int = 6
const FADE_IN_SECS: float = 0.15
const HOLD_SECS: float = 4.0
const FADE_OUT_SECS: float = 0.5
const OUTLINE_SIZE: int = 8
const NAME_COLOR := TrickPopups.ICON_COLOR


## tricks: TrickController.Trick values in the order they were done. points: banked, or what the
## crash voided.
func push(
	username: String,
	is_own: bool,
	tricks: PackedInt32Array,
	points: int,
	multiplier: int,
	crashed: bool
) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.scroll_active = false
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	line.add_theme_font_override("bold_font", bold_font)
	line.add_theme_font_size_override("normal_font_size", font_size)
	line.add_theme_font_size_override("bold_font_size", font_size)
	line.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	line.add_theme_color_override("font_outline_color", Color.BLACK)
	line.text = _format(username, is_own, tricks, points, multiplier, crashed)
	add_child(line)
	move_child(line, 0)
	while get_child_count() > MAX_LINES:
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()

	line.modulate.a = 0.0
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 1.0, FADE_IN_SECS)
	tween.tween_interval(HOLD_SECS)
	tween.tween_property(line, "modulate:a", 0.0, FADE_OUT_SECS)
	tween.tween_callback(line.queue_free)


## [b]Name[/b]  Bailed  Wheelie → Knee Knocker  [b]+1240 ×3[/b] — a bail strikes its lost points.
func _format(
	username: String,
	is_own: bool,
	tricks: PackedInt32Array,
	points: int,
	multiplier: int,
	crashed: bool
) -> String:
	var name_color := RaceLeaderboard.OWN_ROW_COLOR if is_own else NAME_COLOR
	# [lb] escapes BBCode in the username.
	var parts := PackedStringArray(
		["[b][color=#%s]%s[/color][/b]" % [name_color.to_html(false), username.replace("[", "[lb]")]]
	)
	if crashed:
		parts.append("[color=#%s]%s[/color]" % [TrickPopups.OOF_COLOR.to_html(false), tr("FEED_BAILED")])
	var names := PackedStringArray()
	for trick in tricks:
		names.append(TrickController.trick_to_str(trick).capitalize())
	if !names.is_empty():
		parts.append(" → ".join(names))
	if points > 0:
		var points_text := "+%d" % points
		if multiplier > 1:
			points_text += " ×%d" % multiplier
		if crashed:
			points_text = "[s]%s[/s]" % points_text
		var points_color := TrickPopups.OOF_COLOR if crashed else TrickPopups.CALLOUT_COLOR
		parts.append("[b][color=#%s]%s[/color][/b]" % [points_color.to_html(false), points_text])
	return "  ".join(parts)
