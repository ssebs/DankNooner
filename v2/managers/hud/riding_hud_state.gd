@tool
## The riding HUD (Guages, Balance Bar, Boost, etc.)
class_name RidingHUDState extends HUDState

@export var hud_manager: HUDManager

const _RPM_COLOR_LOW := Color(0.103055954, 0.5546875, 0.052001953, 1)
const _RPM_COLOR_HIGH := Color(0.85, 0.1, 0.1, 1)

## Respawn hold bar: only appears once the hold passes this, so a quick tap (in-place respawn)
## doesn't flash it. Fills toward InputStateManager.RESPAWN_HOLD_THRESHOLD.
const _RESPAWN_SHOW_SECS := 0.1
## Boost-gauge "ready" blue while filling; snaps to bright white when the full-respawn fires.
const _RESPAWN_COLOR := Color(0.25, 0.69, 1.0)
const _RESPAWN_COLOR_DONE := Color.WHITE
const _RESPAWN_PULSE_HZ := 2.0
const _RESPAWN_GLOW := 0.35
## How long the "Respawning..." text lingers after a quick tap, so a brief tap still reads.
const _RESPAWN_QUICK_FLASH_SECS := 0.6

@onready var _throttle_bar: ProgressBar = %HUD_ThrottleProgress
@onready var _rpm_bar: ProgressBar = %HUD_RPMProgress

@onready var _brake_label: Label = %HUD_BRAKE
@onready var _clutch_label: Label = %HUD_CLUTCH
@onready var _speed_bar: ProgressBar = %HUD_SpeedProgress
@onready var _speed_num: Label = %HUD_SPEED_NUM
@onready var _gear_label: Label = %HUD_GEAR
@onready var _grip_label: Label = %HUD_GRIP_DGR
@onready var _trick_msg: Label = %HUD_TRICK_MSG
@onready var _game_msg: Label = %HUD_GAME_MSG
@onready var _balance_bar: BalanceBar = %BalanceBar
@onready var _boost_gauge: BoostGauge = %BoostGauge
@onready var _combo_counter: ComboCounter = %ComboCounter
@onready var _minimap: Minimap = %Minimap
@onready var _respawn_bar: ProgressBar = %HUD_RespawnProgress
@onready var _respawn_label: Label = %HUD_RespawnLabel


var player_entity: PlayerEntity
var movement_controller: MovementController
var input_controller: InputController
var gearing_controller: GearingController
var trick_controller: TrickController
var boost_controller: BoostController


var input_state_mgr: InputStateManager = null
var _rpm_fill_style: StyleBoxFlat = null
## Duplicated fill stylebox for the respawn hold bar, so its bg_color can pulse per-frame
## (same trick as _rpm_fill_style).
var _respawn_fill_style: StyleBoxFlat = null
var _respawn_pulse_t: float = 0.0
## Countdown keeping the quick-tap "Respawning..." text up for a split second after release.
var _respawn_flash_t: float = 0.0
## Local-only edge tracking for the boost button, so a press with nothing banked can blink
## the gauge. Purely cosmetic — kept out of the synced boost_prev_held, which the rollback
## tick owns and must not be perturbed by the HUD.
var _prev_boost_held: bool = false
## True while the balance bar is showing the speed wobble (vs a trick). Lets the wobble take the
## bar over and hand it back cleanly.
var _wobble_bar_active: bool = false
## Debug-build-only netfox perf readout. Null on remote instances, in release builds,
## and whenever netfox's perf monitors aren't registered — see show_hud.
var _netfox_debug_label: Label = null
var _netfox_dbg_accum: float = 0.0

func _ready() -> void:
	hide_ui()

func Enter(_state_context: StateContext):
	player_entity = hud_manager.local_player
	if player_entity == null:
		DebugUtils.DebugErrMsg("could not get local player from ridinghudstate")
		return

	movement_controller = player_entity.movement_controller
	input_controller = player_entity.input_controller
	gearing_controller = player_entity.gearing_controller
	trick_controller = player_entity.trick_controller
	boost_controller = player_entity.boost_controller


	if Engine.is_editor_hint():
		return

	input_state_mgr = get_tree().get_first_node_in_group(UtilsConstants.GROUPS["InputStateManager"])

	_rpm_fill_style = _rpm_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	_rpm_bar.add_theme_stylebox_override("fill", _rpm_fill_style)

	_respawn_fill_style = _respawn_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	_respawn_bar.add_theme_stylebox_override("fill", _respawn_fill_style)

	# Discrete events via signals
	gearing_controller.gear_changed.connect(_on_gear_changed)
	trick_controller.trick_started.connect(_on_trick_started)
	trick_controller.trick_ended.connect(_on_trick_ended)
	# Crash message tracks the is_crashed edge (crashed/uncrashed) so a reconciled-away predicted crash clears it.
	player_entity.crashed.connect(_on_crashed)
	player_entity.uncrashed.connect(_on_respawned)
	player_entity.respawned.connect(_on_respawned)
	# Local-only: expand the minimap into the full map while IN_MAP.
	input_state_mgr.input_state_changed.connect(_on_input_state_changed)
	input_state_mgr.respawn_quick_fired.connect(_on_respawn_quick_fired)

	# Manual inits
	_on_gear_changed(1)
	_balance_bar.hide()


	show_ui()

func Exit(_state_context: StateContext):
	# Enter() bails before wiring in the editor or when there's no local player,
	# so there's nothing to disconnect in those cases.
	if Engine.is_editor_hint() or player_entity == null:
		hide_ui()
		return

	gearing_controller.gear_changed.disconnect(_on_gear_changed)
	trick_controller.trick_started.disconnect(_on_trick_started)
	trick_controller.trick_ended.disconnect(_on_trick_ended)
	player_entity.crashed.disconnect(_on_crashed)
	player_entity.uncrashed.disconnect(_on_respawned)
	player_entity.respawned.disconnect(_on_respawned)
	input_state_mgr.input_state_changed.disconnect(_on_input_state_changed)
	input_state_mgr.respawn_quick_fired.disconnect(_on_respawn_quick_fired)

	hide_ui()

func Physics_Update(delta: float):
	if Engine.is_editor_hint():
		return

	# Poll continuous values directly from controllers
	_throttle_bar.value = int(input_controller.nfx_throttle * 100)
	_brake_label.text = tr("HUD_BRAKE_F").format(
		{
			"front": int(input_controller.nfx_front_brake * 100),
			"rear": int(input_controller.nfx_rear_brake * 100),
		}
	)

	if input_controller.nfx_clutch_held:
		_clutch_label.text = tr("HUD_CLUTCH_IN")
	else:
		_clutch_label.text = tr("HUD_CLUTCH_OUT")

	var rpm_ratio := gearing_controller.get_rpm_ratio()
	_rpm_bar.value = int(rpm_ratio * 100)
	_rpm_fill_style.bg_color = _RPM_COLOR_LOW.lerp(_RPM_COLOR_HIGH, clampf(rpm_ratio, 0.0, 1.0))
	_speed_bar.value = int(movement_controller.speed)
	_speed_num.text = "%d" % int(movement_controller.speed)
	_grip_label.text = tr("HUD_GRIP").format({"value": int(player_entity.grip_usage * 100)})

	# The tank-slapper takes the balance bar over from the trick display while active.
	if movement_controller.is_wobbling:
		if not _wobble_bar_active:
			_init_wobble_bar()
			_balance_bar.update_warn_markers()
			_balance_bar.show()
			_wobble_bar_active = true
		_balance_bar.current_val = rad_to_deg(movement_controller.wobble_angle)
	else:
		if _wobble_bar_active:
			_wobble_bar_active = false
			_balance_bar.hide()
		_balance_bar.current_val = rad_to_deg(movement_controller.pitch_angle)

	# Boost meter + combo multiplier are server-authoritative (TrickManager) and arrive
	# via RollbackSynchronizer, so poll the synced vars rather than tracking them here.
	_boost_gauge.current_val = boost_controller.boost_amount
	_boost_gauge.set_spending(boost_controller.is_boosting)

	# A press under one full segment is silently ignored by BoostController — blink so the
	# rejection is visible instead of feeling like a dead button. Mid-burn presses don't
	# count as rejected.
	var boost_held: bool = input_controller.nfx_boost_held
	if boost_held and not _prev_boost_held:
		if not boost_controller.is_boosting and boost_controller.boost_amount < 1.0:
			_boost_gauge.flash_rejected()
	_prev_boost_held = boost_held
	# A crash voids the run (TrickManager), but combo_multiplier / combo_time stay frozen
	# until the respawn clears them — force x1 + inactive so the loss reads immediately.
	var comboing: bool = trick_controller.combo_time > 0.0 and not player_entity.is_crashed
	var combo: int = trick_controller.combo_multiplier if comboing else 1
	_combo_counter.set_combo(combo, comboing)

	# Respawn feedback. A tap shows "Respawning..." for a split second; holding past
	# _RESPAWN_SHOW_SECS switches to "Full respawning..." with the bar charging toward the
	# full-respawn threshold. The bar hits solid white at 100% so you can see you held long enough.
	_respawn_flash_t = maxf(_respawn_flash_t - delta, 0.0)
	var respawn_hold := input_state_mgr.get_respawn_hold_time()
	if respawn_hold > _RESPAWN_SHOW_SECS:
		_respawn_label.text = tr("HUD_FULL_RESPAWNING")
		_respawn_label.visible = true
		_respawn_bar.visible = true
		var progress := clampf(respawn_hold / InputStateManager.RESPAWN_HOLD_THRESHOLD, 0.0, 1.0)
		_respawn_bar.value = progress * 100.0
		if progress >= 1.0:
			_respawn_fill_style.bg_color = _RESPAWN_COLOR_DONE
		else:
			_respawn_pulse_t += delta
			var glow := (sin(_respawn_pulse_t * TAU * _RESPAWN_PULSE_HZ) * 0.5 + 0.5) * _RESPAWN_GLOW
			_respawn_fill_style.bg_color = _RESPAWN_COLOR.lerp(Color.WHITE, glow)
	elif respawn_hold > 0.0 or _respawn_flash_t > 0.0:
		# Early press, or the lingering flash after a quick tap — quick respawn intent, no bar.
		_respawn_label.text = tr("HUD_RESPAWNING")
		_respawn_label.visible = true
		_respawn_bar.visible = false
	else:
		_respawn_label.visible = false
		_respawn_bar.visible = false

	# 1 Hz netfox readout — rollback resim volume + state property traffic, for spotting
	# input starvation / correction storms during playtests.
	_netfox_dbg_accum -= delta
	if _netfox_debug_label != null and _netfox_dbg_accum <= 0.0:
		_netfox_dbg_accum = 1.0
		_netfox_debug_label.text = (
			"rb ticks/s: %d | rb ms: %.1f | state props full/sent: %d/%d"
			% [
				Performance.get_custom_monitor(&"netfox/Rollback ticks simulated"),
				Performance.get_custom_monitor(&"netfox/Rollback loop duration (ms)"),
				Performance.get_custom_monitor(&"netfox/Full state properties count"),
				Performance.get_custom_monitor(&"netfox/Sent state properties count"),
			]
		)


## Symmetric ±crash-angle range with warn bands at the crash edges (danger at the extremes).
func _init_wobble_bar():
	var limit := movement_controller.wobble_crash_angle_deg
	_balance_bar.min_val = -limit
	_balance_bar.max_val = limit
	_balance_bar.warn_low_val = -limit * 0.7
	_balance_bar.warn_high_val = limit * 0.7


##### TODO - move to balance_bar.gd
func _init_balance_bar(trick_type: TrickController.Trick):
	var bd = player_entity.bike_definition
	match trick_type:
		TrickController.Trick.STOPPIE:
			_balance_bar.min_val = - bd.max_stoppie_angle_deg
			_balance_bar.max_val = 0.0
			# # No dedicated stoppie balance point — warn band sits in the usable middle
			_balance_bar.warn_low_val = - bd.max_stoppie_angle_deg * 0.8
			_balance_bar.warn_high_val = - bd.max_stoppie_angle_deg * 0.3
		TrickController.Trick.WHEELIE_MOD, TrickController.Trick.WHEELIE_SITTING:
			_balance_bar.min_val = 0.0
			_balance_bar.max_val = bd.max_wheelie_angle_deg
			_balance_bar.warn_low_val = (
				bd.wheelie_balance_point_deg - bd.wheelie_balance_point_width_deg
			)
			_balance_bar.warn_high_val = (
				bd.wheelie_balance_point_deg + bd.wheelie_balance_point_width_deg
			)


#region signal handlers
func _on_input_state_changed(new_state: InputStateManager.InputState) -> void:
	_minimap.set_expanded(new_state == InputStateManager.InputState.IN_MAP)


func _on_gear_changed(new_gear: int):
	_gear_label.text = tr("HUD_GEAR").format({"value": new_gear})


func _on_trick_started(trick_type: TrickController.Trick):
	_trick_msg.text = TrickController.Trick.keys()[trick_type]
	_trick_msg.visible = true

	if (
		trick_type
		in [
			TrickController.Trick.WHEELIE_SITTING,
			TrickController.Trick.WHEELIE_MOD,
			TrickController.Trick.STOPPIE
		]
	):
		_init_balance_bar(trick_type)
		_balance_bar.update_warn_markers()
		_balance_bar.show()


func _on_trick_ended(_trick_type: TrickController.Trick):
	_trick_msg.visible = false
	_balance_bar.hide()


func _on_crashed(_peer_id: int):
	_game_msg.text = tr("HUD_CRASHED")
	_game_msg.visible = true


func _on_respawned():
	_game_msg.visible = false


## Tap (quick in-place respawn) fired — keep "Respawning..." up briefly even for a fast tap.
func _on_respawn_quick_fired():
	_respawn_flash_t = _RESPAWN_QUICK_FLASH_SECS


#endregion


func show_ui() -> void:
	ui.visible = true
	_minimap.activate(player_entity)

	# Only the local client reaches show_ui, so the overlay never spawns on remote
	# player instances. netfox registers its perf monitors only when NetworkPerformance
	# is enabled (debug builds / netfox_perf tag), and Performance.get_custom_monitor
	# errors on a monitor that was never added — so skip the label entirely when the
	# monitors are absent instead of erroring once a second.
	# Guarded on null so pause re-showing the HUD doesn't stack a second label.
	if (
		_netfox_debug_label == null
		and OS.has_feature("debug")
		and Performance.has_custom_monitor(&"netfox/Rollback ticks simulated")
	):
		_netfox_debug_label = Label.new()
		_netfox_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_netfox_debug_label.add_theme_font_size_override("font_size", 12)
		_netfox_debug_label.position = Vector2(8, 8)
		add_child(_netfox_debug_label)


## Server-side: forward the local racer's next-checkpoint marker to the owning
## client's minimap. Called from the race gamemodes.
func push_checkpoint_marker(peer_id: int, pos: Vector3, has_target: bool) -> void:
	_minimap.rpc_set_checkpoint.rpc_id(peer_id, pos, has_target)


func hide_ui() -> void:
	ui.visible = false
	_minimap.deactivate()


## Called from player_entity.gd's do_respawn
func do_reset():
	_gear_label.text = tr("HUD_GEAR").format({"value": 1})
	_trick_msg.visible = false
	_game_msg.visible = false
	_combo_counter.do_reset()
	_prev_boost_held = false
	_wobble_bar_active = false


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if hud_manager == null:
		issues.append("hud_manager must not be empty")
	return issues
