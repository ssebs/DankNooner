@tool
## Kill-feed style log of every rider's banked combos and bails, mid-left, newest on top. Each line
## flashes in (HUDFlash) and fades out after HOLD_SECS. Fed by RidingHUDState from the server's
## TrickManager.
class_name TrickFeed extends VBoxContainer

@export var font_size: int = 20

const MAX_LINES: int = 6
const HOLD_SECS: float = 4.0
const FADE_OUT_SECS: float = 0.5
## Each line's flash in: your lines gold, bails red.
const FLASH_COLOR := Color(2.4, 2.4, 2.4)
const FLASH_OWN_COLOR := Color(3.2, 2.6, 0.8)
const FLASH_BAIL_COLOR := Color(3.2, 0.6, 0.6)
const NAME_COLOR := Color.WHITE
## Your name, like your leaderboard row.
const OWN_NAME_COLOR := UtilsConstants.UI_BLUE
## A combo longer than this shows only its last tricks, plus how many were cut.
const MAX_TRICK_NAMES: int = 3


## tricks: TrickController.Trick values in the order they were done. points: banked, or what the
## crash voided. launch_m: how far a bail threw the rider from the bike.
func push(
	username: String,
	is_own: bool,
	tricks: PackedInt32Array,
	points: int,
	multiplier: int,
	crashed: bool,
	launch_m: float
) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.scroll_active = false
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.add_theme_font_size_override("normal_font_size", font_size)
	line.add_theme_font_size_override("bold_font_size", font_size)
	line.text = _format(username, is_own, tricks, points, multiplier, crashed, launch_m)
	add_child(line)
	move_child(line, 0)
	while get_child_count() > MAX_LINES:
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()

	var flash_color := FLASH_BAIL_COLOR if crashed else FLASH_OWN_COLOR if is_own else FLASH_COLOR
	HUDFlash.flash_in(line, flash_color)
	var tween := line.create_tween()
	tween.tween_interval(HOLD_SECS)
	tween.tween_property(line, "modulate:a", 0.0, FADE_OUT_SECS)
	tween.tween_callback(line.queue_free)


## [b]Name[/b]  Bailed 23m  …Wheelie → Knee Knocker → Drift (+2)  [b]+1240 ×3[/b] — a bail strikes
## its lost points.
func _format(
	username: String,
	is_own: bool,
	tricks: PackedInt32Array,
	points: int,
	multiplier: int,
	crashed: bool,
	launch_m: float
) -> String:
	# [lb] escapes BBCode in the username.
	var name_color := OWN_NAME_COLOR if is_own else NAME_COLOR
	var shown_name := (
		"[color=#%s]%s[/color]" % [name_color.to_html(false), username.replace("[", "[lb]")]
	)
	var parts := PackedStringArray(["[b]%s[/b]" % shown_name])
	if crashed:
		parts.append(
			(
				"[color=#%s]%s %dm[/color]"
				% [TrickPopups.OOF_COLOR.to_html(false), tr("FEED_BAILED"), launch_m]
			)
		)
	var names := PackedStringArray()
	for trick in tricks:
		names.append(TrickController.trick_to_str(trick).capitalize())
	if names.size() > MAX_TRICK_NAMES:
		var cut := names.size() - MAX_TRICK_NAMES
		parts.append("…%s (+%d)" % [" → ".join(names.slice(cut)), cut])
	elif !names.is_empty():
		parts.append(" → ".join(names))
	if points > 0:
		var points_text := "+%d" % points
		if multiplier > 1:
			points_text += " ×%d" % multiplier
		if crashed:
			points_text = "[s]%s[/s]" % points_text
		if crashed:
			points_text = "[color=#%s]%s[/color]" % [TrickPopups.OOF_COLOR.to_html(false), points_text]
		parts.append("[b]%s[/b]" % points_text)
	return "  ".join(parts)
