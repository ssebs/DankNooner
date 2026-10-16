extends RefCounted
## Plays free-roam activities through their own input: the fuel-up pump by cursor (camera
## unproject + mouse warp, use_item clicks), the garage through GarageUI's buttons.
## Warping moves the real OS cursor, so only one peer may play a pump at a time (see TestRunner).

## A full tank reads as this
const FULL := 0.99
const PUMP_TIMEOUT_S := 30.0

## The TestRunner. Untyped: it preloads this script, and a cyclic preload won't resolve.
var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


## Grab the handle, fill at the cap, hang it up, press End.
func play_fuel_up(pump: FuelUpMinigame) -> bool:
	var handle: Node3D = pump.get_node("%HandleMarkerClick")
	var rest := handle.global_position
	_point_at(rest)
	await _runner.get_tree().process_frame
	await _click()
	var grabbed := func(): return pump.get_prompt_key() != "FUELUP_GRAB"
	if not await _runner.wait_until(grabbed, "the pump handle grab", PUMP_TIMEOUT_S):
		return false

	var player := _runner.get_tree().get_first_node_in_group(UtilsConstants.GROUPS["LocalPlayer"])
	var cap: Marker3D = player.gas_cap_marker
	Input.action_press(&"use_item")
	var filling := func():
		# Recoil shoves the cursor; keep pulling it back onto the cap
		_point_at(cap.global_position)
		return pump.fill >= FULL or pump.get_prompt_key() == "FUELUP_RETURN"
	var filled: bool = await _runner.wait_until(filling, "the tank to fill", PUMP_TIMEOUT_S)
	Input.action_release(&"use_item")
	if pump.spilled > 0.0:
		_runner.violate("fuel-up spilled %.2f with the cursor on the cap" % pump.spilled)
	if !filled:
		return false

	var hung_up := func():
		_point_at(rest)
		return pump.get_prompt_key() == "FUELUP_GRAB"
	if not await _runner.wait_until(hung_up, "the pump handle to hang up", PUMP_TIMEOUT_S):
		return false
	_point_at((pump.get_node("%EndBtn") as Node3D).global_position)
	await _runner.get_tree().process_frame
	await _click()
	return true


## Buys the first affordable bike skin not owned yet, then leaves. Checks it landed in the save.
func play_garage() -> bool:
	var garage_ui: GarageUI = _runner.hud_manager.garage_hud_state.get_node("%GarageUI")
	var save_manager: SaveManager = _runner.save_manager
	var bikes := SkinScanner.scan_skin_dir(GarageUI.BIKE_SKINS_DIR)
	var target_index := -1
	for i in bikes.size():
		var path: String = bikes.values()[i]
		var price: int = (load(path) as BikeSkinDefinition).price
		if !save_manager.is_owned(path) and price <= save_manager.get_player_definition().money:
			target_index = i
			break
	if target_index == -1:
		_runner.violate("garage has no affordable unowned bike to buy")
		return false
	var target_path: String = bikes.values()[target_index]

	# Opens on the active loadout, whose first GarageRow is its bike
	_rows(garage_ui)[0].pressed.emit()
	await _runner.get_tree().process_frame
	_rows(garage_ui)[target_index].pressed.emit()
	await _runner.get_tree().process_frame
	(garage_ui.get_node("%ConfirmYesBtn") as Button).pressed.emit()
	await _runner.get_tree().process_frame
	(garage_ui.get_node("%LeaveBtn") as Button).pressed.emit()
	# GarageHUDState.Exit commits the edits to disk
	var hud: HUDManager = _runner.hud_manager
	var left := func(): return hud.state_machine.current_state != hud.garage_hud_state
	if not await _runner.wait_until(left, "the garage to close"):
		return false

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
	viewport.warp_mouse(viewport.get_camera_3d().unproject_position(world_pos))


func _click() -> void:
	Input.action_press(&"use_item")
	await _runner.get_tree().process_frame
	await _runner.get_tree().process_frame
	Input.action_release(&"use_item")
