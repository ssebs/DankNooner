@tool
## Borderlands-style trick feedback over the riding HUD — all local and display-only:
##  - right of center: live "+N" for the combo in progress, popped when the server banks it,
##    or turned into a red "OOF!" when a crash voids it
##  - left of center: a callout for every trick started (TRICK_CALLOUTS, else the trick's
##    name), timed HOLD_CALLOUTS, and any server-sent callout
## Sfx: tada on a combo multiplier step up, ding on a score pop. Callouts stay silent.
## A pop grows small -> big, then drifts outward with a slight tilt and fades. Each pop is its
## own Label, so rapid pops stack instead of resetting.
class_name TrickPopups extends Control

## Trick -> callout text key, popped when the trick starts. Tricks missing here pop their name.
const TRICK_CALLOUTS: Dictionary = {
	TrickController.Trick.BACKFLIP: "CALLOUT_SICK_FLIP",
	TrickController.Trick.FRONTFLIP: "CALLOUT_SICK_FLIP",
	TrickController.Trick.WHEELIE_SITTING: "CALLOUT_WHEELIE",
	TrickController.Trick.WHEELIE_MOD: "CALLOUT_WHEELIE",
	TrickController.Trick.KNEE_KNOCKER: "CALLOUT_KNEE_KNOCKER",
	TrickController.Trick.HIGH_CHAIR: "CALLOUT_HIGH_CHAIR",
}
## Callout text key -> condition: the rider holds one of `tricks` (at the wheelie balance point
## too, if `balance_point`) for `hold` seconds. Fires once per continuous hold.
const HOLD_CALLOUTS: Dictionary = {
	"CALLOUT_NICE_DRIFT": {"tricks": [TrickController.Trick.DRIFT], "hold": 2.0},
	"CALLOUT_DANKNOONER":
	{
		"tricks": [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD],
		"hold": 3.0,
		"balance_point": true,
	},
}
## Cycled in order so back-to-back crashes don't repeat.
const OOF_KEYS: Array[String] = ["CALLOUT_OOF_1", "CALLOUT_OOF_2", "CALLOUT_OOF_3", "CALLOUT_OOF_4"]
const OOF_COLOR := Color(1.0, 0.2, 0.15)
const CALLOUT_COLOR := Color(1.0, 0.85, 0.2)

const FONT_SIZE: int = 40
const OUTLINE_SIZE: int = 10
## Pop origins, as offsets from this control's center.
const SCORE_ORIGIN := Vector2(140.0, -60.0)
const CALLOUT_ORIGIN := Vector2(-140.0, -60.0)
const POP_SECS: float = 0.2
const POP_START_SCALE: float = 0.3
const POP_PEAK_SCALE: float = 1.3
const DRIFT_SECS: float = 1.0
## Drift for a right-side pop; mirrored on x for the left side.
const DRIFT_PX := Vector2(90.0, -110.0)
## Max tilt either way (radians); the sign is random per pop.
const TILT_RAD: float = 0.25
const FADE_SECS: float = 0.4

## Set by RidingHUDState on Enter — the local player's.
var audio_manager: AudioManager = null

var _live: Label = null
## Multiplier seen last frame, to catch the step up.
var _last_multiplier: int = 1
## Trick seen last frame, to catch a new one starting.
var _last_trick: TrickController.Trick = TrickController.Trick.NONE
## Last held trick called out this combo. Hovering at the wheelie threshold flickers
## current_trick on/off, so re-entering it inside the same combo stays quiet.
var _last_named: TrickController.Trick = TrickController.Trick.NONE
## Callout key -> seconds its condition has held; absent while it doesn't.
var _held: Dictionary[String, float] = {}
var _oof_index: int = 0


func _ready():
	if Engine.is_editor_hint():
		return
	_live = _make_label(Color.WHITE)
	_live.visible = false
	add_child(_live)


## Every frame, for the local rider: the live combo points and callout conditions.
func track(player: PlayerEntity, points_per_second: float, delta: float) -> void:
	var tc := player.trick_controller
	_live.visible = tc.combo_time > 0.0 and not player.is_crashed
	if _live.visible and tc.combo_multiplier > _last_multiplier:
		audio_manager.play_tada()
	_last_multiplier = tc.combo_multiplier if _live.visible else 1
	if _live.visible:
		_live.text = "+%d" % int(tc.combo_score * points_per_second * tc.combo_multiplier)
		_live.modulate = _tier_color(tc.combo_multiplier)
		_place(_live, SCORE_ORIGIN)

	_track_trick_start(tc)
	_track_hold_callouts(player, delta)


func pop_score(points: int, multiplier: int) -> void:
	_spawn("+%d" % points, _tier_color(multiplier), SCORE_ORIGIN, 1.0)
	audio_manager.play_ding()


## The live combo was voided by a crash.
func pop_oof() -> void:
	_live.visible = false
	_spawn(tr(OOF_KEYS[_oof_index]), OOF_COLOR, SCORE_ORIGIN, 1.0)
	_oof_index = (_oof_index + 1) % OOF_KEYS.size()


## text is already localized.
func pop_callout(text: String) -> void:
	_spawn(text, CALLOUT_COLOR, CALLOUT_ORIGIN, -1.0)


## Held tricks flicker at their thresholds, so they're called out once per combo; one-shot
## tricks (flips, taps) every time.
func _track_trick_start(tc: TrickController) -> void:
	var trick := tc.current_trick
	if tc.combo_time <= 0.0:
		_last_named = TrickController.Trick.NONE
	var started := trick != _last_trick and trick != TrickController.Trick.NONE
	_last_trick = trick
	if !started or trick == _last_named:
		return
	if TrickController.HELD_TRICK_SCORE.has(trick):
		_last_named = trick
	if TRICK_CALLOUTS.has(trick):
		pop_callout(tr(TRICK_CALLOUTS[trick]))
	else:
		pop_callout("%s!" % TrickController.trick_to_str(trick).capitalize().to_upper())


func _track_hold_callouts(player: PlayerEntity, delta: float) -> void:
	for key: String in HOLD_CALLOUTS:
		var cond: Dictionary = HOLD_CALLOUTS[key]
		var met: bool = (
			not player.is_crashed
			and player.trick_controller.current_trick in cond["tricks"]
			and (!cond.get("balance_point", false) or player.movement_controller.in_balance_point)
		)
		if !met:
			_held.erase(key)
			continue
		var before: float = _held.get(key, -INF)
		_held[key] = 0.0 if before == -INF else before + delta
		if before < cond["hold"] and _held[key] >= cond["hold"]:
			pop_callout(tr(key))


## side: 1 drifts right, -1 drifts left.
func _spawn(text: String, color: Color, origin: Vector2, side: float) -> void:
	var label := _make_label(color)
	label.text = text
	add_child(label)
	_place(label, origin)
	label.scale = Vector2.ONE * POP_START_SCALE

	var tween := label.create_tween()
	var grow := tween.tween_property(label, "scale", Vector2.ONE * POP_PEAK_SCALE, POP_SECS)
	grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Drift, tilt and fade run together once the pop lands.
	tween.set_parallel()
	var drift := Vector2(DRIFT_PX.x * side, DRIFT_PX.y)
	tween.chain().tween_property(label, "position", label.position + drift, DRIFT_SECS)
	tween.tween_property(label, "rotation", TILT_RAD * signf(randf() - 0.5), DRIFT_SECS)
	tween.tween_property(label, "modulate:a", 0.0, FADE_SECS).set_delay(DRIFT_SECS - FADE_SECS)
	tween.chain().tween_callback(label.queue_free)


func _make_label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Centers the label on origin (relative to this control's center), pivoting about its middle.
func _place(label: Label, origin: Vector2) -> void:
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.position = size / 2.0 + origin - label.size / 2.0


func _tier_color(multiplier: int) -> Color:
	var tiers := ComboCounter.TIER_COLORS
	return tiers[mini(multiplier - 1, tiers.size() - 1)]
