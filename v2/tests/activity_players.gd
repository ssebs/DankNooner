extends RefCounted
## Plays free-roam activities through their own input: the fuel-up pump by cursor (camera
## unproject + mouse warp, use_item clicks), the garage through GarageUI's buttons.
## Warping moves the real OS cursor, so only one peer may play a pump at a time (see TestRunner).

## A full tank reads as this
const FULL := 0.99
## Whole pump session, mouse grant to End; a working one takes about fill_secs
const PUMP_TIMEOUT_S := 10.0
const GARAGE_TIMEOUT_S := 5.0
## Per-frame cap movement (m) that counts as the bike being parked
const SETTLED_M := 0.0005
## On-screen tip-to-cap error (viewport px) that counts as lined up. An OS pixel is a few
## viewport px in a tiled window, so tighter never settles
const AIM_PX := 12.0
const AIM_GAIN := 0.5

## The TestRunner. Untyped: it preloads this script, and a cyclic preload won't resolve.
var _runner: Node
var _diag_next_ms := 0  # TEMP


func _init(runner: Node) -> void:
	_runner = runner


## Grab the handle, fill at the cap, hang it up, press End.
func play_fuel_up(pump: FuelUpMinigame) -> bool:
	var handle: Node3D = pump.get_node("%HandleMarkerClick")
	var rest := handle.global_position
	var player := _runner.get_tree().get_first_node_in_group(UtilsConstants.GROUPS["LocalPlayer"])
	var cap: Marker3D = player.gas_cap_marker
	var deadline := Time.get_ticks_msec() + int(PUMP_TIMEOUT_S * 1000.0)
	# The session starts while the bike eases out of its lean, and the pump measures the cap at
	# the grab: wait for it to park, as a human's reaction time would
	var last := Vector3.INF
	while cap.global_position.distance_to(last) > SETTLED_M:
		if Time.get_ticks_msec() > deadline:
			_runner.violate("the gas cap never stopped moving")
			return false
		last = cap.global_position
		await _runner.get_tree().process_frame
	var cap_at_grab := cap.global_position
	# Retried: a click is lost if the cursor wasn't on the handle yet (a warp lands a frame late)
	while pump.get_prompt_key() == "FUELUP_GRAB":
		if Time.get_ticks_msec() > deadline:
			_runner.violate("timed out waiting for the pump handle grab")
			return false
		_point_at(rest)
		await _runner.get_tree().process_frame
		await _click()

	var tip: Node3D = pump.get_node("%HandleMarkerTip")
	# Spraying before the tip is in spills, so line it up first
	var aimed := func(): return _steer_tip(tip, cap) < AIM_PX
	if not await _runner.wait_until(aimed, "the nozzle tip on the cap", _left_s(deadline)):
		return false
	Input.action_press(&"use_item")
	var filling := func():
		# Recoil shoves the cursor; keep pulling the tip back onto the cap
		_steer_tip(tip, cap)
		return pump.fill >= FULL or pump.get_prompt_key() == "FUELUP_RETURN"
	var filled: bool = await _runner.wait_until(filling, "the tank to fill", _left_s(deadline))
	Input.action_release(&"use_item")
	if pump.spilled > 0.0:
		_runner.violate("fuel-up spilled %.2f with the cursor on the cap" % pump.spilled)
	if !filled:
		return false

	var hung_up := func():
		_point_at(rest)
		return pump.get_prompt_key() == "FUELUP_GRAB"
	if not await _runner.wait_until(hung_up, "the pump handle to hang up", _left_s(deadline)):
		# TEMP diagnostic
		DebugUtils.DebugMsg(
			"[test] DIAG hang-up: grip %.3fm from rest, cap moved %.3fm since grab"
			% [handle.global_position.distance_to(rest), cap.global_position.distance_to(cap_at_grab)]
		)
		return false
	_point_at((pump.get_node("%EndBtn") as Node3D).global_position)
	await _runner.get_tree().process_frame
	await _click()
	return true


## Buys the first affordable character skin not owned yet, then leaves. Checks it landed in the
## save. Characters, not bikes: every bike skin is free.
func play_garage() -> bool:
	var garage_ui: GarageUI = _runner.hud_manager.garage_hud_state.get_node("%GarageUI")
	var save_manager: SaveManager = _runner.save_manager
	var player_def := save_manager.get_player_definition()
	var current: CharacterSkinDefinition = player_def.loadouts[player_def.active_loadout_index].character
	var characters := SkinScanner.scan_skin_dir(GarageUI.CHARACTER_SKINS_DIR)
	var target_index := -1
	for i in characters.size():
		var path: String = characters.values()[i]
		var price: int = (load(path) as CharacterSkinDefinition).price
		# Pressing the current one is a no-op
		var is_current: bool = current != null and characters.keys()[i] == current.skin_name
		if !is_current and !save_manager.is_owned(path) and price <= player_def.money:
			target_index = i
			break
	if target_index == -1:
		_runner.violate("garage has no affordable unowned character to buy")
	else:
		# Opens on the active loadout: GarageRows bike, bike colors, character
		_rows(garage_ui)[2].pressed.emit()
		await _runner.get_tree().process_frame
		# The character page leads with the profile-default row
		_rows(garage_ui)[target_index + 1].pressed.emit()
		await _runner.get_tree().process_frame
		(garage_ui.get_node("%ConfirmYesBtn") as Button).pressed.emit()
		await _runner.get_tree().process_frame
	# Left even after a failure, so the rider isn't stranded in the garage
	(garage_ui.get_node("%LeaveBtn") as Button).pressed.emit()
	# GarageHUDState.Exit commits the edits to disk
	var hud: HUDManager = _runner.hud_manager
	var left := func(): return hud.state_machine.current_state != hud.garage_hud_state
	if not await _runner.wait_until(left, "the garage to close", GARAGE_TIMEOUT_S) or target_index == -1:
		return false

	var target_path: String = characters.values()[target_index]
	var on_disk := DictJSONSaverLoader.load_json_from_file(save_manager.save_path)
	if target_path not in on_disk["progression"]["owned"]:
		_runner.violate("garage purchase of %s didn't reach the save" % target_path)
		return false
	return true


## GarageUI's GarageRows, top to bottom (text rows are skipped).
func _rows(garage_ui: GarageUI) -> Array[GarageRow]:
	var rows: Array[GarageRow] = []
	for child in garage_ui.get_node("%Rows").get_children():
		if child is GarageRow:
			rows.append(child)
	return rows


func _point_at(world_pos: Vector3) -> void:
	var viewport := _runner.get_viewport()
	_diag("point", viewport.get_camera_3d().unproject_position(world_pos))
	viewport.warp_mouse(viewport.get_camera_3d().unproject_position(world_pos))


# TEMP diagnostic: is the shared OS cursor reaching this window?
func _diag(what: String, target: Vector2) -> void:
	if Time.get_ticks_msec() < _diag_next_ms:
		return
	_diag_next_ms = Time.get_ticks_msec() + 1000
	var window := _runner.get_window()
	DebugUtils.DebugMsg(
		"[test] DIAG %s target=%s viewport_mouse=%s os_mouse=%s win=%s+%s focused=%s mode=%s"
		% [
			what, target, _runner.get_viewport().get_mouse_position(),
			DisplayServer.mouse_get_position(), window.position, window.size,
			window.has_focus(), DisplayServer.mouse_get_mode(),
		]
	)


## The cursor carries the grip, not the tip, and the handle swings as it nears the cap, so steer
## by the tip's on-screen error. Returns that error (px) before this step.
func _steer_tip(tip: Node3D, cap: Node3D) -> float:
	var viewport := _runner.get_viewport()
	var camera := viewport.get_camera_3d()
	var error := camera.unproject_position(cap.global_position) - camera.unproject_position(tip.global_position)
	_diag("steer err=%.1f" % error.length(), viewport.get_mouse_position() + error * AIM_GAIN)
	# Damped: a warp only reaches the handle a frame later
	viewport.warp_mouse(viewport.get_mouse_position() + error * AIM_GAIN)
	return error.length()


## Seconds until `deadline` (ticks msec)
static func _left_s(deadline: int) -> float:
	return (deadline - Time.get_ticks_msec()) / 1000.0


func _click() -> void:
	Input.action_press(&"use_item")
	await _runner.get_tree().process_frame
	await _runner.get_tree().process_frame
	Input.action_release(&"use_item")
