## Plays trick anims from the shared rider IK library on a CustomAnimPlayer. Shared by
## AnimationController (PlayerEntity) and RiderVisual (garage, NPCs). Anims are authored on
## PlayerEntity's IKAnimationPlayer, which saves into LIBRARY.
class_name TrickAnimator extends RefCounted

enum PlayMode {
	ONE_SHOT,  # play(anim, 1.0, false) — fires once, auto-fades when finished
	LOOP_WHILE_LATCHED,  # play(anim, 1.0, false) — same call as ONE_SHOT today; kept distinct for intent
	HOLD_WHILE_LATCHED,  # play_one_shot — settles + holds at end pose; pairs with reverse_on_end
}

const LIBRARY: AnimationLibrary = preload("res://resources/player/ik_anim_lib.res")

var _runner: CustomAnimPlayer
var _by_trick: Dictionary = {}


func _init(runner: CustomAnimPlayer) -> void:
	_runner = runner
	for entry in _build_entries():
		entry.anim = load_anim(entry.anim_name)
		_by_trick[entry.trick] = entry


## Any anim in LIBRARY (null if missing), with `%UniqueName:property` track paths rewritten to
## `IKTargets/UniqueName:property` so CustomAnimPlayer.find_track resolves them. All IK markers
## live under IKTargets, so the rewrite is mechanical.
static func load_anim(anim_name: String) -> Animation:
	if not LIBRARY.has_animation(anim_name):
		return null
	var anim := LIBRARY.get_animation(anim_name)
	for i in anim.get_track_count():
		var path_str := String(anim.track_get_path(i))
		if path_str.begins_with("%"):
			anim.track_set_path(i, NodePath("IKTargets/" + path_str.substr(1)))
	return anim


func has_anim(trick: TrickController.Trick) -> bool:
	return _by_trick.has(trick) and _by_trick[trick].anim != null


func start(trick: TrickController.Trick) -> void:
	var entry: _Entry = _by_trick.get(trick)
	if entry == null or entry.anim == null:
		return
	match entry.play_mode:
		PlayMode.HOLD_WHILE_LATCHED:
			# Settle into pose, hold while latched. If a reverse-out is mid-flight (re-entry
			# during the unwind), flip it back to forward instead of starting a new layer.
			if entry.layer != null and entry.layer.is_playing():
				entry.layer.speed = 1.0
				entry.layer.hold_at_end = true
				entry.layer.target_weight = 1.0
			else:
				entry.layer = _runner.play_one_shot(entry.anim, 1.0)
		_:
			# ONE_SHOT / LOOP_WHILE_LATCHED both call play(); end() doesn't stop them,
			# so the anim plays through fully and auto-fades at end.
			if entry.layer == null or not entry.layer.is_playing():
				entry.layer = _runner.play(entry.anim, 1.0, false)


func end(trick: TrickController.Trick) -> void:
	var entry: _Entry = _by_trick.get(trick)
	if entry == null or not entry.reverse_on_end:
		return
	# Reverse from current time back to 0 — rider unwinds out of the pose smoothly.
	# When time hits 0, hold_at_end=false makes the layer auto-fade and clear itself.
	if entry.layer != null and entry.layer.is_playing():
		entry.layer.speed = -1.0
		entry.layer.hold_at_end = false
		entry.layer.target_weight = 1.0


## Forget the layers after the runner dropped them (crash / respawn flush).
func clear() -> void:
	for entry: _Entry in _by_trick.values():
		entry.layer = null


## Data row for a trick anim. To add a trick: append one _make_entry(...) row in
## _build_entries(). No new vars, no init branches, no cleanup spots.
class _Entry:
	var trick: int  # TrickController.Trick
	var anim_name: String
	var play_mode: int  # PlayMode
	var reverse_on_end: bool
	var anim: Animation = null
	var layer: CustomAnimPlayer.Layer = null


static func _make_entry(
	trick: int, anim_name: String, play_mode: int, reverse_on_end: bool
) -> _Entry:
	var e := _Entry.new()
	e.trick = trick
	e.anim_name = anim_name
	e.play_mode = play_mode
	e.reverse_on_end = reverse_on_end
	return e


static func _build_entries() -> Array[_Entry]:
	return [
		# One-shots play through and auto-fade; holds (high chair, t-pose, knee knocker) unwind on end.
		_make_entry(TrickController.Trick.HEEL_CLICKER, "heel_clicker", PlayMode.ONE_SHOT, false),
		_make_entry(
			TrickController.Trick.HIGH_CHAIR, "high_chair", PlayMode.HOLD_WHILE_LATCHED, true
		),
		_make_entry(TrickController.Trick.TWO_LEFT_FEET, "two_left_feet", PlayMode.ONE_SHOT, false),
		_make_entry(TrickController.Trick.KICKFLIP, "kickflip", PlayMode.ONE_SHOT, false),
		_make_entry(TrickController.Trick.BUNNY_HOP, "bunny_hop", PlayMode.ONE_SHOT, false),
		_make_entry(TrickController.Trick.SPREAD_EAGLE, "spread_eagle", PlayMode.ONE_SHOT, false),
		_make_entry(TrickController.Trick.SUPERMAN, "superman", PlayMode.ONE_SHOT, false),
		_make_entry(TrickController.Trick.T_POSE, "t_pose", PlayMode.HOLD_WHILE_LATCHED, true),
		_make_entry(
			TrickController.Trick.KNEE_KNOCKER, "knee_knocker", PlayMode.HOLD_WHILE_LATCHED, true
		),
	]
