@tool
## Borderlands-style trick feedback over the riding HUD — all local and display-only:
##  - below center, under the rider: live "+N" for the combo in progress, popped when the server
##    banks it, or turned into a red "OOF!" when a crash voids it. BONUS_COLOR while holding a race
##    challenge's hint trick (suggested tricks score 2x), and on a pop that included one. The
##    combo's gold xN (x2 up) sits to its right, punched on every step up
##  - under the score: the bike icon, tilted to the bike's pitch vs its balance point while
##    wheelieing / stoppieing / airborne, plus the race wheelie stopwatch
##  - up and right of center: a callout for every trick started (TRICK_CALLOUTS, else the trick's
##    name), timed HOLD_CALLOUTS, and any server-sent callout
## Sfx: tada on a combo multiplier step up, ding on a score pop. Callouts stay silent.
## Each pop enters with a HUDFlash verb (callouts wheelie, scores pop, bails shake), holds, then
## sinks as it fades. Each is its own Label, so rapid pops stack instead of resetting.
class_name TrickPopups extends Control

## Trick -> callout text key, popped when the trick starts. Tricks missing here pop their name.
const TRICK_CALLOUTS: Dictionary = {
	TrickController.Trick.BACKFLIP: "CALLOUT_SICK_FLIP",
	TrickController.Trick.FRONTFLIP: "CALLOUT_SICK_FLIP",
	TrickController.Trick.WHEELIE_SITTING: "CALLOUT_WHEELIE",
	TrickController.Trick.WHEELIE_MOD: "CALLOUT_WHEELIE",
	TrickController.Trick.KNEE_KNOCKER: "CALLOUT_KNEE_KNOCKER",
	TrickController.Trick.HIGH_CHAIR: "CALLOUT_HIGH_CHAIR",
	TrickController.Trick.DRIFT_WHEELIE: "CALLOUT_DRIFT_WHEELIE",
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
const OOF_COLOR := UtilsConstants.UI_RED
const CALLOUT_COLOR := UtilsConstants.UI_GOLD
const SCORE_COLOR := Color.WHITE
## The live score and its pop while a suggested trick doubled it.
const BONUS_COLOR := UtilsConstants.UI_GOLD
const MULTIPLIER_COLOR := UtilsConstants.UI_GOLD
const MULTIPLIER_GAP_PX: float = 12.0

## Pop origins, as offsets from this control's center.
const SCORE_ORIGIN := Vector2(30.0, 96.0)
const CALLOUT_ORIGIN := Vector2(210.0, -250.0)
## Gap from the score's bottom to the stopwatch row (negative tucks it up — the icon's art has
## transparent padding). The row's left edge lines up with the score's.
const WHEELIE_GAP_Y: float = 12.0
const WHEELIE_ICON := preload("res://resources/img/Logos/DankNoonerLogo_BikeOnlyHorizontal.png")
const TINT_SHADER := preload("res://resources/shaders/hud_tint.gdshader")
const WHEELIE_ICON_PX: float = 64.0
## The icon's rear / front wheel contact points, as a fraction of its size — it wheelies /
## stoppies about these.
const WHEELIE_ICON_PIVOT := Vector2(0.35, 0.63)
const STOPPIE_ICON_PIVOT := Vector2(0.65, 0.63)
const ICON_MIN_SCALE: float = 0.6
const ICON_MAX_SCALE: float = 1.3
const ICON_SMOOTH_SPEED: float = 12.0
## Icon colors: blue approaching the balance point, gold in it, red past it; each edge blends over
## ICON_BLEND_DEG.
const ICON_COLOR := UtilsConstants.UI_BLUE # the art's own blue
const ICON_BP_COLOR := UtilsConstants.UI_GOLD
const ICON_HOT_COLOR := UtilsConstants.UI_RED
const ICON_BLEND_DEG: float = 6.0
## The icon's throb in the balance point: scale depth and rate.
const ICON_THROB: float = 0.08
const ICON_THROB_HZ: float = 2.5
## A pop holds, then sinks by SINK_PX as it fades.
const HOLD_SECS: float = 0.5
const SINK_SECS: float = 0.6
const SINK_PX := Vector2(0.0, 60.0)
## A new callout pushes the ones still on screen down a row, so rapid callouts stack instead of piling
## up at CALLOUT_ORIGIN. The push eases in at CALLOUT_STACK_SPEED.
const CALLOUT_STACK_PX: float = 50.0
const CALLOUT_STACK_SPEED: float = 12.0

## Set by RidingHUDState on Enter — the local player's.
var audio_manager: AudioManager = null

var _live: Label = null
## The combo's xN, right of the live score.
var _multiplier: Label = null
var _wheelie_row: HBoxContainer = null
var _wheelie_icon: TextureRect = null
var _wheelie_label: Label = null
var _icon_material: ShaderMaterial = null
## show_pitch_icon's targets — the HUD updates on physics ticks, so _process eases toward them.
var _icon_rotation: float = 0.0
var _icon_scale: float = 1.0
var _icon_offset := Vector2.ZERO
var _icon_target_tint := ICON_COLOR
var _icon_tint := ICON_COLOR
## Multiplier seen last frame, to catch the step up.
var _last_multiplier: int = 1
## Trick seen last frame, to catch a new one starting.
var _last_trick: TrickController.Trick = TrickController.Trick.NONE
## Last held trick called out this combo. Hovering at the wheelie threshold flickers
## current_trick on/off, so re-entering it inside the same combo stays quiet.
var _last_named: TrickController.Trick = TrickController.Trick.NONE
## Callout key -> seconds its condition has held; absent while it doesn't.
var _held: Dictionary[String, float] = {}
## A flip was completed last frame, to catch it landing into a wheelie / stoppie.
var _was_flipped: bool = false
var _oof_index: int = 0
## Callouts on screen, oldest first — each in its own holder, so the stack push moves the holder and
## never fights the label's drift tween.
var _callouts: Array[Control] = []


func _ready():
	if Engine.is_editor_hint():
		return
	_live = _make_label(Color.WHITE)
	_live.visible = false
	add_child(_live)
	_multiplier = _make_label(MULTIPLIER_COLOR)
	_multiplier.visible = false
	add_child(_multiplier)

	_wheelie_row = HBoxContainer.new()
	_wheelie_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheelie_row.add_theme_constant_override("separation", 0)
	_wheelie_row.visible = false
	add_child(_wheelie_row)
	# A container resets its children's rotation on every re-sort — the icon rotates inside a
	# plain Control slot the row sizes instead.
	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2.ONE * WHEELIE_ICON_PX
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheelie_row.add_child(icon_slot)
	_wheelie_icon = TextureRect.new()
	_wheelie_icon.texture = WHEELIE_ICON
	_wheelie_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wheelie_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wheelie_icon.size = Vector2.ONE * WHEELIE_ICON_PX
	_wheelie_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_material = ShaderMaterial.new()
	_icon_material.shader = TINT_SHADER
	_wheelie_icon.material = _icon_material
	icon_slot.add_child(_wheelie_icon)
	_wheelie_label = _make_label(Color.WHITE)
	_wheelie_row.add_child(_wheelie_label)


## Every frame, for the local rider: the live combo points and callout conditions.
func track(
	player: PlayerEntity, points_per_second: float, bonus_tricks: PackedInt32Array, delta: float
) -> void:
	var tc := player.trick_controller
	_live.visible = tc.combo_time > 0.0 and not player.is_crashed
	_multiplier.visible = _live.visible and tc.combo_multiplier > 1
	if _live.visible and tc.combo_multiplier > _last_multiplier:
		audio_manager.play_tada()
		HUDFlash.punch(_multiplier)
	_last_multiplier = tc.combo_multiplier if _live.visible else 1
	if _live.visible:
		_live.text = "+%d" % int(tc.combo_score * points_per_second * tc.combo_multiplier)
		_multiplier.text = tr("HUD_COMBO").format({"value": tc.combo_multiplier})
		var bonus := tc.current_trick in bonus_tricks
		_live.modulate = BONUS_COLOR if bonus else SCORE_COLOR
	# Placed even while hidden — the icon row anchors under it.
	_center_on(_live, size / 2.0 + SCORE_ORIGIN)
	_multiplier.reset_size()
	_multiplier.position = _live.position + Vector2(_live.size.x + MULTIPLIER_GAP_PX, 0.0)

	_track_trick_start(tc)
	_track_hold_callouts(player, delta)
	if _was_flipped and tc.is_landed_in_trick() and not player.is_crashed:
		pop_callout(tr("CALLOUT_STUCK_LANDING"))
	_was_flipped = tc.has_flipped()


func pop_score(points: int, _multiplier: int, bonus: bool) -> void:
	HUDFlash.pop(_spawn("+%d" % points, BONUS_COLOR if bonus else SCORE_COLOR, SCORE_ORIGIN))
	audio_manager.play_ding()


## The live combo was voided by a crash.
func pop_oof() -> void:
	_live.visible = false
	HUDFlash.shake(_spawn(tr(OOF_KEYS[_oof_index]), OOF_COLOR, SCORE_ORIGIN))
	_oof_index = (_oof_index + 1) % OOF_KEYS.size()


## The bike icon, tilted to pitch (degrees, + = wheelie; the icon faces right, so a wheelie tilts
## it counter-clockwise). window is (min, low, high, max): the pitch range and its balance point.
## The icon grows toward the balance point, throbs inside it, and shrinks past it (away from
## level), shaking there only on a wheelie / stoppie; see ICON_COLOR for its colors. pivot:
## rotation point as a fraction of the icon's size. timer: the race wheelie stopwatch's seconds, 0
## to hide it.
func show_pitch_icon(pitch: float, window: Vector4, pivot: Vector2, timer: float) -> void:
	var low := window.y
	var high := window.z
	# A wheelie / stoppie window sits on one side of level; air's spans both and has no over-rotation.
	var one_sided := window.x >= 0.0 or window.w <= 0.0
	_icon_offset = Vector2.ZERO
	if pitch >= low and pitch <= high:
		var throb := sin(Time.get_ticks_msec() / 1000.0 * TAU * ICON_THROB_HZ) * ICON_THROB
		_icon_scale = ICON_MAX_SCALE * (1.0 + throb)
		_icon_target_tint = ICON_BP_COLOR
	else:
		# 0 at the window's edge, 1 at the end of the range on that side.
		var edge := high if pitch > high else low
		var end := window.w if pitch > high else window.x
		var t := clampf((pitch - edge) / (end - edge), 0.0, 1.0)
		var past := (pitch > high and high >= 0.0) or (pitch < low and low <= 0.0)
		_icon_scale = lerpf(ICON_MAX_SCALE, ICON_MIN_SCALE, t)
		if past and one_sided:
			_icon_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * HUDFlash.SHAKE_PX
		var s := clampf(absf(pitch - edge) / ICON_BLEND_DEG, 0.0, 1.0)
		_icon_target_tint = ICON_BP_COLOR.lerp(ICON_HOT_COLOR if past else ICON_COLOR, s)
	_icon_rotation = - deg_to_rad(pitch)
	_wheelie_icon.pivot_offset = _wheelie_icon.size * pivot
	_wheelie_label.text = tr("RACE_WHEELIE_ATTEMPT").format({"time": "%.1f" % timer})
	_wheelie_label.visible = timer > 0.0
	if not _wheelie_row.visible:
		_ease_icon(1.0) # just appeared — start at the target instead of easing from stale values
	_wheelie_row.visible = true
	_wheelie_row.reset_size()
	# The score label is re-placed (centered on SCORE_ORIGIN) every frame by track().
	_wheelie_row.position = Vector2(_live.position.x, _live.position.y + _live.size.y + WHEELIE_GAP_Y)


func hide_pitch_icon() -> void:
	_wheelie_row.visible = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Newest sits at its origin, each older one a row further down
	var stack_weight := 1.0 - exp(-CALLOUT_STACK_SPEED * delta)
	for i in _callouts.size():
		var row := _callouts.size() - 1 - i
		_callouts[i].position.y = lerpf(_callouts[i].position.y, row * CALLOUT_STACK_PX, stack_weight)
	if _wheelie_row.visible:
		_ease_icon(1.0 - exp(-ICON_SMOOTH_SPEED * delta))


func _ease_icon(weight: float) -> void:
	_wheelie_icon.rotation = lerp_angle(_wheelie_icon.rotation, _icon_rotation, weight)
	_wheelie_icon.scale = _wheelie_icon.scale.lerp(Vector2.ONE * _icon_scale, weight)
	_wheelie_icon.position = _wheelie_icon.position.lerp(_icon_offset, weight)
	_icon_tint = _icon_tint.lerp(_icon_target_tint, weight)
	_icon_material.set_shader_parameter("tint", _icon_tint)


## text is already localized.
func pop_callout(text: String) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_callouts.append(holder)
	HUDFlash.wheelie(spawn_pop(holder, text, CALLOUT_COLOR, size / 2.0 + CALLOUT_ORIGIN, SINK_PX))
	# The pop frees its label when done; the holder goes with it
	holder.child_exiting_tree.connect(_drop_callout.bind(holder).unbind(1))


func _drop_callout(holder: Control) -> void:
	_callouts.erase(holder)
	holder.queue_free()


## Held tricks flicker at their thresholds, so they're called out once per combo; one-shot
## tricks (flips, taps) every time.
func _track_trick_start(tc: TrickController) -> void:
	var trick := tc.current_trick
	if tc.combo_time <= 0.0:
		_last_named = TrickController.Trick.NONE
	var started := trick != _last_trick and trick != TrickController.Trick.NONE
	_last_trick = trick
	# A new trick is the live score's next climb.
	if started and _live.visible:
		HUDFlash.pop(_live)
	if !started or trick == _last_named:
		return
	# The nose dropping mid-slide turns a drift wheelie into a plain drift — already called out.
	if trick == TrickController.Trick.DRIFT and _last_named == TrickController.Trick.DRIFT_WHEELIE:
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


func _spawn(text: String, color: Color, origin: Vector2) -> Label:
	return spawn_pop(self, text, color, size / 2.0 + origin, SINK_PX)


## A pop centered on `center` in `parent`'s space: holds, then moves by `drift` as it fades. The
## caller gives it its entry verb (HUDFlash). Static so other HUD elements (MoneyLabel) pop the
## same way.
static func spawn_pop(
	parent: Control, text: String, color: Color, center: Vector2, drift: Vector2
) -> Label:
	var label := _make_label(color)
	label.text = text
	parent.add_child(label)
	_center_on(label, center)

	var tween := label.create_tween()
	tween.tween_interval(HOLD_SECS)
	tween.set_parallel()
	tween.chain().tween_property(label, "position", label.position + drift, SINK_SECS)
	tween.tween_property(label, "modulate:a", 0.0, SINK_SECS)
	tween.chain().tween_callback(label.queue_free)
	return label


static func _make_label(color: Color) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"PopupLabel"
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Centers the label on `center`, pivoting about its middle.
static func _center_on(label: Label, center: Vector2) -> void:
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.position = center - label.size / 2.0

