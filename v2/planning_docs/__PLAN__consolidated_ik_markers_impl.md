# Consolidated IK Marker System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all IK markers to PlayerEntity, remove duplicate markers from BikeSkin and CharacterSkin, and make rider poses work correctly per-bike.

**Architecture:** All 11 IK target markers live under `PlayerEntity/VisualRoot/IKTargets/`. BikeSkin loses its marker nodes (data stays in BikeSkinDefinition .tres). CharacterSkin loses its IKTargets node. AnimationController syncs hand/foot targets from bike geometry each tick, reads positions from definition instead of marker nodes.

**Tech Stack:** Godot 4.6, GDScript, netfox rollback

**Verification:** No automated tests — verify in Godot editor (IK posing) and by running the game. CLAUDE.md says only the human runs the project.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `player/characters/scripts/ik_controller.gd` | Modify | Remove @export markers, add `set_targets()` taking all 11 |
| `player/player_entity.gd` | Modify | Add @export for all 11 markers, update `_init_ik()` |
| `player/bikes/scripts/bike_skin.gd` | Modify | Remove marker nodes/code, update steering proxy |
| `player/characters/scripts/character_skin.gd` | Modify | Remove IKTargets references |
| `player/controllers/animation_controller.gd` | Modify | Rename proxy→target, update sync + editor tools |
| `player/player_entity.tscn` | Modify | Add IKTargets node, rename proxies, add new markers |
| `player/characters/character_skin.tscn` | Modify | Remove IKTargets node and children |
| `player/bikes/bike_skin.tscn` | Modify | Remove all Marker3D nodes |

---

### Task 1: Update IKController Interface

**Files:**
- Modify: `player/characters/scripts/ik_controller.gd`

- [ ] **Step 1: Remove @export markers, add set_targets()**

Replace the @export vars and `set_bike_markers()` with a single `set_targets()` that takes all 11 markers. The vars become regular vars (like `ik_left_hand` already is).

```gdscript
# Remove these @export lines (lines 7-12):
@export var ik_left_arm_magnet: Marker3D
@export var ik_right_arm_magnet: Marker3D
@export var ik_left_leg_magnet: Marker3D
@export var ik_right_leg_magnet: Marker3D
@export var ik_chest: Marker3D
@export var ik_head: Marker3D

# Replace with regular vars (alongside existing bike marker vars):
var ik_left_arm_magnet: Marker3D
var ik_right_arm_magnet: Marker3D
var ik_left_leg_magnet: Marker3D
var ik_right_leg_magnet: Marker3D
var ik_chest: Marker3D
var ik_head: Marker3D
```

Replace `set_bike_markers()` with `set_targets()`:

```gdscript
func set_targets(
	seat: Marker3D,
	left_hand: Marker3D,
	right_hand: Marker3D,
	left_foot: Marker3D,
	right_foot: Marker3D,
	chest: Marker3D,
	head: Marker3D,
	left_arm_magnet: Marker3D,
	right_arm_magnet: Marker3D,
	left_leg_magnet: Marker3D,
	right_leg_magnet: Marker3D
) -> void:
	butt_pos = seat
	ik_left_hand = left_hand
	ik_right_hand = right_hand
	ik_left_foot = left_foot
	ik_right_foot = right_foot
	ik_chest = chest
	ik_head = head
	ik_left_arm_magnet = left_arm_magnet
	ik_right_arm_magnet = right_arm_magnet
	ik_left_leg_magnet = left_leg_magnet
	ik_right_leg_magnet = right_leg_magnet
```

- [ ] **Step 2: Update _get_configuration_warnings()**

Remove the checks for @export markers since they're set at runtime now:

```gdscript
func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if char_skin == null:
		issues.append("char_skin must be set")
	return issues
```

---

### Task 2: Update PlayerEntity Exports and Init

**Files:**
- Modify: `player/player_entity.gd`

- [ ] **Step 1: Replace proxy @exports with target @exports**

Remove old proxy exports and add all 11 marker exports:

```gdscript
# Remove these (lines 29-32):
@export var left_hand_proxy: Marker3D
@export var right_hand_proxy: Marker3D
@export var left_foot_proxy: Marker3D
@export var right_foot_proxy: Marker3D

# Replace with all 11 IK target markers:
@export_group("IK Targets")
@export var butt_target: Marker3D
@export var left_hand_target: Marker3D
@export var right_hand_target: Marker3D
@export var left_foot_target: Marker3D
@export var right_foot_target: Marker3D
@export var chest_target: Marker3D
@export var head_target: Marker3D
@export var left_arm_magnet: Marker3D
@export var right_arm_magnet: Marker3D
@export var left_leg_magnet: Marker3D
@export var right_leg_magnet: Marker3D
```

- [ ] **Step 2: Update _init_ik()**

```gdscript
func _init_ik():
	var ik_ctrl = character_skin.ik_controller

	# Position butt from bike definition
	butt_target.position = bike_definition.seat_marker_position

	# Pass all 11 markers to IKController
	ik_ctrl.set_targets(
		butt_target,
		left_hand_target, right_hand_target,
		left_foot_target, right_foot_target,
		chest_target, head_target,
		left_arm_magnet, right_arm_magnet,
		left_leg_magnet, right_leg_magnet
	)

	_apply_rider_pose_from_definition()

	ik_ctrl._create_ik()
	character_skin.enable_ik()
```

- [ ] **Step 3: Update _apply_rider_pose_from_definition()**

Access PlayerEntity's own markers instead of going through `character_skin.ik_controller`:

```gdscript
func _apply_rider_pose_from_definition():
	var bd = bike_definition

	if bd.chest_position is Vector3 and bd.chest_position != Vector3.ZERO:
		chest_target.position = bd.chest_position
	if bd.chest_rotation is Vector3 and bd.chest_rotation != Vector3.ZERO:
		chest_target.rotation = bd.chest_rotation
	if bd.head_position is Vector3 and bd.head_position != Vector3.ZERO:
		head_target.position = bd.head_position
	if bd.head_rotation is Vector3 and bd.head_rotation != Vector3.ZERO:
		head_target.rotation = bd.head_rotation
	if bd.left_arm_magnet_position is Vector3 and bd.left_arm_magnet_position != Vector3.ZERO:
		left_arm_magnet.position = bd.left_arm_magnet_position
	if bd.right_arm_magnet_position is Vector3 and bd.right_arm_magnet_position != Vector3.ZERO:
		right_arm_magnet.position = bd.right_arm_magnet_position
	if bd.left_leg_magnet_position is Vector3 and bd.left_leg_magnet_position != Vector3.ZERO:
		left_leg_magnet.position = bd.left_leg_magnet_position
	if bd.right_leg_magnet_position is Vector3 and bd.right_leg_magnet_position != Vector3.ZERO:
		right_leg_magnet.position = bd.right_leg_magnet_position
	if bd.left_hand_rotation is Vector3 and bd.left_hand_rotation != Vector3.ZERO:
		left_hand_target.rotation = bd.left_hand_rotation
	if bd.right_hand_rotation is Vector3 and bd.right_hand_rotation != Vector3.ZERO:
		right_hand_target.rotation = bd.right_hand_rotation
	if bd.left_foot_rotation is Vector3 and bd.left_foot_rotation != Vector3.ZERO:
		left_foot_target.rotation = bd.left_foot_rotation
	if bd.right_foot_rotation is Vector3 and bd.right_foot_rotation != Vector3.ZERO:
		right_foot_target.rotation = bd.right_foot_rotation
```

- [ ] **Step 4: Update _get_configuration_warnings()**

Replace old proxy checks with new target checks:

```gdscript
# Remove old proxy checks, add:
if butt_target == null:
	issues.append("butt_target must not be empty")
if left_hand_target == null:
	issues.append("left_hand_target must not be empty")
if right_hand_target == null:
	issues.append("right_hand_target must not be empty")
if left_foot_target == null:
	issues.append("left_foot_target must not be empty")
if right_foot_target == null:
	issues.append("right_foot_target must not be empty")
if chest_target == null:
	issues.append("chest_target must not be empty")
if head_target == null:
	issues.append("head_target must not be empty")
if left_arm_magnet == null:
	issues.append("left_arm_magnet must not be empty")
if right_arm_magnet == null:
	issues.append("right_arm_magnet must not be empty")
if left_leg_magnet == null:
	issues.append("left_leg_magnet must not be empty")
if right_leg_magnet == null:
	issues.append("right_leg_magnet must not be empty")
```

---

### Task 3: Update BikeSkin — Remove Markers

**Files:**
- Modify: `player/bikes/scripts/bike_skin.gd`

- [ ] **Step 1: Remove marker @onready refs and editor buttons**

Remove all of these:

```gdscript
# Remove these @onready declarations:
@onready var training_wheels_marker: Marker3D = %TrainingWheelsModsMarker
@onready var seat_marker: Marker3D = %SeatMarker
@onready var left_handlebar_marker: Marker3D = %LeftHandleBarMarker
@onready var left_peg_marker: Marker3D = %LeftPegMarker
@onready var front_wheel_ground_marker: Marker3D = %FrontWheelGroundMarker
@onready var rear_wheel_ground_marker: Marker3D = %RearWheelGroundMarker
@onready var rear_wheel_back_marker: Marker3D = %RearWheelBackMarker
@onready var front_wheel_front_marker: Marker3D = %FrontWheelFrontMarker

# Remove these editor buttons:
@export_tool_button("Save Markers to resource") var save_markers_btn = _save_markers_to_resource
@export_tool_button("Load Markers from resource") var load_markers_btn = _load_markers_from_resource
```

- [ ] **Step 2: Remove _load/_save_markers methods**

Delete `_load_markers_from_resource()` and `_save_markers_to_resource()` entirely.

- [ ] **Step 3: Update _apply_definition()**

Remove the `_load_markers_from_resource()` call:

```gdscript
func _apply_definition():
	_spawn_mesh()
	_set_mesh_colors()
	_create_steering_handlebar_proxy()
	if Engine.is_editor_hint():
		mesh_skin.owner = self
```

- [ ] **Step 4: Update _create_steering_handlebar_proxy()**

Read handlebar position from definition instead of marker node:

```gdscript
func _create_steering_handlebar_proxy():
	if not has_steering():
		steering_handlebar_marker = null
		return
	var steering_node = mesh_skin.steering_rotation_node
	var proxy = Marker3D.new()
	proxy.name = "SteeringHandleBarProxy"
	steering_node.add_child(proxy)
	# Position proxy from definition values in BikeSkin local space
	var hb_pos = skin_definition.left_handlebar_marker_position
	var hb_rot_deg = skin_definition.left_handlebar_marker_rotation_degrees
	var hb_rot = Vector3(
		deg_to_rad(hb_rot_deg.x), deg_to_rad(hb_rot_deg.y), deg_to_rad(hb_rot_deg.z)
	)
	proxy.global_transform = global_transform * Transform3D(Basis.from_euler(hb_rot), hb_pos)
	steering_handlebar_marker = proxy
```

Note: `steering_handlebar_marker` is set to `null` when there's no steering (was previously set to `left_handlebar_marker` which no longer exists). AnimationController will handle the no-steering fallback.

---

### Task 4: Update AnimationController

**Files:**
- Modify: `player/controllers/animation_controller.gd`

- [ ] **Step 1: Rename proxy references to target references**

Throughout the file, rename:
- `_proxy_markers_enabled` → `_targets_synced_from_bike`
- `enable_proxy_markers()` → `enable_target_sync()`
- `disable_proxy_markers()` → `disable_target_sync()`
- `_sync_proxies_from_bike()` → `_sync_targets_from_bike()`

- [ ] **Step 2: Update _sync_targets_from_bike()**

Replace bike_skin marker node access with definition values. The steering handlebar proxy still exists on bike_skin. For the peg, compute from definition:

```gdscript
func _sync_targets_from_bike() -> void:
	if bike_skin == null:
		return
	# Steering handlebar proxy still lives on bike_skin (rotates with steering)
	var hb: Marker3D = bike_skin.steering_handlebar_marker
	if hb == null:
		return

	var hb_parent := hb.get_parent() as Node3D

	# Peg transform computed from definition (no marker node needed)
	var peg_pos = _bd.left_peg_marker_position
	var peg_rot_deg = _bd.left_peg_marker_rotation_degrees
	var peg_rot = Vector3(
		deg_to_rad(peg_rot_deg.x), deg_to_rad(peg_rot_deg.y), deg_to_rad(peg_rot_deg.z)
	)
	var peg_local = Transform3D(Basis.from_euler(peg_rot), peg_pos)
	var peg_parent = bike_skin

	var def: BikeSkinDefinition = _bd if _bd else bike_skin.skin_definition

	var left_hand_local := _local_with_rotation_override(
		hb.transform, def.left_hand_rotation if def else Vector3.ZERO
	)
	var right_hand_local := _local_with_rotation_override(
		_mirror_transform_x(hb.transform), def.right_hand_rotation if def else Vector3.ZERO
	)
	var left_foot_local := _local_with_rotation_override(
		peg_local, def.left_foot_rotation if def else Vector3.ZERO
	)
	var right_foot_local := _local_with_rotation_override(
		_mirror_transform_x(peg_local), def.right_foot_rotation if def else Vector3.ZERO
	)

	player_entity.left_hand_target.global_transform = hb_parent.global_transform * left_hand_local
	player_entity.right_hand_target.global_transform = hb_parent.global_transform * right_hand_local
	player_entity.left_foot_target.global_transform = peg_parent.global_transform * left_foot_local
	player_entity.right_foot_target.global_transform = peg_parent.global_transform * right_foot_local
```

- [ ] **Step 3: Update initialize()**

Replace `_ik_ctrl` references for base position caching with `player_entity` marker refs:

```gdscript
func initialize() -> void:
	if character_skin == null or bike_skin == null or visual_root == null:
		DebugUtils.DebugErrMsg(
			"AnimationController: Missing character_skin, bike_skin, or visual_root"
		)
		return

	_ik_ctrl = character_skin.ik_controller
	_bd = player_entity.bike_definition

	if _ik_ctrl and _ik_ctrl.butt_pos:
		_base_butt_pos = _ik_ctrl.butt_pos.position
	if player_entity.chest_target:
		_base_chest_pos = player_entity.chest_target.position
		_base_chest_rot = player_entity.chest_target.rotation

	_base_visual_root_position = visual_root.position
	_base_visual_root_rotation = visual_root.rotation

	if ik_anim_player:
		ik_anim_player.root_node = ik_anim_player.get_path_to(visual_root)

	_sync_targets_from_bike()
```

- [ ] **Step 4: Update _riding_common()**

Replace `_ik_ctrl.ik_chest` and `_ik_ctrl.butt_pos` with `player_entity` refs:

```gdscript
func _riding_common(delta: float) -> void:
	visual_root.rotation.z = lerpf(visual_root.rotation.z, _roll, _blend)

	var target_chest_y = _roll * deg_to_rad(30)
	player_entity.chest_target.rotation.y = lerpf(
		player_entity.chest_target.rotation.y, target_chest_y, _blend
	)

	var lean_x_offset = clampf(visual_root.rotation.z, -max_butt_offset, max_butt_offset)
	var target_butt_x = _base_butt_pos.x - lean_x_offset
	var target_chest_x = _base_chest_pos.x - lean_x_offset
	_ik_ctrl.butt_pos.position.x = lerpf(_ik_ctrl.butt_pos.position.x, target_butt_x, _blend)
	player_entity.chest_target.position.x = lerpf(
		player_entity.chest_target.position.x, target_chest_x, _blend
	)

	var lean_input = input_controller.nfx_lean
	var target_chest_pitch = _base_chest_rot.x - lean_input * deg_to_rad(max_chest_lean_pitch_deg)
	var target_chest_z = _base_chest_pos.z + lean_input * max_chest_z_offset
	var target_butt_z = _base_butt_pos.z + lean_input * max_butt_z_offset
	player_entity.chest_target.rotation.x = lerpf(
		player_entity.chest_target.rotation.x, target_chest_pitch, _blend
	)
	player_entity.chest_target.position.z = lerpf(
		player_entity.chest_target.position.z, target_chest_z, _blend
	)
	_ik_ctrl.butt_pos.position.z = lerpf(_ik_ctrl.butt_pos.position.z, target_butt_z, _blend)

	var steer_input := _roll if _targets_synced_from_bike else 0.0
	bike_skin.rotate_steering(steer_input, delta)
	bike_skin.rotate_wheels(movement_controller.speed, delta, trick_controller.is_in_wheelie())

	if _targets_synced_from_bike:
		_sync_targets_from_bike()
```

- [ ] **Step 5: Update _reset_to_base_positions()**

```gdscript
func _reset_to_base_positions() -> void:
	if _ik_ctrl and _ik_ctrl.butt_pos:
		_ik_ctrl.butt_pos.position = _base_butt_pos
	if player_entity.chest_target:
		player_entity.chest_target.position = _base_chest_pos
		player_entity.chest_target.rotation = _base_chest_rot
	if visual_root:
		visual_root.position = _base_visual_root_position
		visual_root.rotation = _base_visual_root_rotation
	if bike_skin:
		bike_skin.rotation.x = 0.0
```

- [ ] **Step 6: Update editor tools**

Update `_editor_init_ik_from_bike()`:

```gdscript
func _editor_init_ik_from_bike() -> void:
	if bike_skin == null or character_skin == null:
		DebugUtils.DebugErrMsg("AnimationController: bike_skin and character_skin must be set")
		return
	if player_entity == null:
		DebugUtils.DebugErrMsg("AnimationController: player_entity must be set for editor init")
		return

	var ik_ctrl = character_skin.ik_controller
	var def = bike_skin.skin_definition

	if ik_anim_player:
		ik_anim_player.stop()

	# Position butt from definition
	player_entity.butt_target.position = def.seat_marker_position

	# Pass all markers to IKController
	ik_ctrl.set_targets(
		player_entity.butt_target,
		player_entity.left_hand_target, player_entity.right_hand_target,
		player_entity.left_foot_target, player_entity.right_foot_target,
		player_entity.chest_target, player_entity.head_target,
		player_entity.left_arm_magnet, player_entity.right_arm_magnet,
		player_entity.left_leg_magnet, player_entity.right_leg_magnet
	)

	_sync_targets_from_bike()

	# Load rider pose from definition
	if def.chest_position is Vector3 and def.chest_position != Vector3.ZERO:
		player_entity.chest_target.position = def.chest_position
	if def.chest_rotation is Vector3 and def.chest_rotation != Vector3.ZERO:
		player_entity.chest_target.rotation = def.chest_rotation
	if def.head_position is Vector3 and def.head_position != Vector3.ZERO:
		player_entity.head_target.position = def.head_position
	if def.head_rotation is Vector3 and def.head_rotation != Vector3.ZERO:
		player_entity.head_target.rotation = def.head_rotation
	if def.left_arm_magnet_position is Vector3 and def.left_arm_magnet_position != Vector3.ZERO:
		player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position is Vector3 and def.right_arm_magnet_position != Vector3.ZERO:
		player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position is Vector3 and def.left_leg_magnet_position != Vector3.ZERO:
		player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position is Vector3 and def.right_leg_magnet_position != Vector3.ZERO:
		player_entity.right_leg_magnet.position = def.right_leg_magnet_position

	ik_ctrl._create_ik()
	character_skin.enable_ik()
	disable_target_sync()
```

Update `_editor_save_default_pose()`:

```gdscript
func _editor_save_default_pose() -> void:
	var def = bike_skin.skin_definition
	if def == null:
		DebugUtils.DebugErrMsg("AnimationController: missing bike_skin definition")
		return

	def.chest_position = player_entity.chest_target.position
	def.chest_rotation = player_entity.chest_target.rotation
	def.head_position = player_entity.head_target.position
	def.head_rotation = player_entity.head_target.rotation
	def.left_arm_magnet_position = player_entity.left_arm_magnet.position
	def.right_arm_magnet_position = player_entity.right_arm_magnet.position
	def.left_leg_magnet_position = player_entity.left_leg_magnet.position
	def.right_leg_magnet_position = player_entity.right_leg_magnet.position
	# Save butt position as seat marker
	def.seat_marker_position = player_entity.butt_target.position

	# Hand/foot rotations in bike marker parent space
	var hb: Marker3D = bike_skin.steering_handlebar_marker
	var hb_parent := hb.get_parent() as Node3D if hb else bike_skin as Node3D
	var peg_parent := bike_skin as Node3D

	if player_entity.left_hand_target:
		def.left_hand_rotation = _rotation_in_parent_space(
			player_entity.left_hand_target, hb_parent
		)
	if player_entity.right_hand_target:
		def.right_hand_rotation = _rotation_in_parent_space(
			player_entity.right_hand_target, hb_parent
		)
	if player_entity.left_foot_target:
		def.left_foot_rotation = _rotation_in_parent_space(
			player_entity.left_foot_target, peg_parent
		)
	if player_entity.right_foot_target:
		def.right_foot_rotation = _rotation_in_parent_space(
			player_entity.right_foot_target, peg_parent
		)

	var err = ResourceSaver.save(def)
	if err == OK:
		DebugUtils.DebugMsg("AnimationController: Saved rider pose to %s" % def.resource_path)
	else:
		DebugUtils.DebugErrMsg(
			"AnimationController: Failed to save BikeSkinDefinition, error: %s" % err
		)
```

Update `_editor_reset_to_default_pose()`:

```gdscript
func _editor_reset_to_default_pose() -> void:
	var def = bike_skin.skin_definition
	if def == null:
		DebugUtils.DebugErrMsg("AnimationController: missing bike_skin definition")
		return

	if def.chest_position is Vector3:
		player_entity.chest_target.position = def.chest_position
	if def.chest_rotation is Vector3:
		player_entity.chest_target.rotation = def.chest_rotation
	if def.head_position is Vector3:
		player_entity.head_target.position = def.head_position
	if def.head_rotation is Vector3:
		player_entity.head_target.rotation = def.head_rotation
	if def.left_arm_magnet_position is Vector3:
		player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position is Vector3:
		player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position is Vector3:
		player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position is Vector3:
		player_entity.right_leg_magnet.position = def.right_leg_magnet_position
	player_entity.butt_target.position = def.seat_marker_position
	_sync_targets_from_bike()
```

- [ ] **Step 7: Update _editor_sync_pose_from_definition()**

```gdscript
func _editor_sync_pose_from_definition() -> void:
	if bike_skin == null or player_entity == null:
		return
	var def = bike_skin.skin_definition
	if def == null:
		return

	player_entity.chest_target.position = def.chest_position
	player_entity.chest_target.rotation = def.chest_rotation
	player_entity.head_target.position = def.head_position
	player_entity.head_target.rotation = def.head_rotation
	player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	player_entity.right_leg_magnet.position = def.right_leg_magnet_position
	_sync_targets_from_bike()
```

- [ ] **Step 8: Remove ik_ctrl references from _get_configuration_warnings()**

The AnimationController no longer needs to check for ik_ctrl markers. Remove any references. Keep checks for visual_root, character_skin, bike_skin, movement_controller, input_controller, ik_anim_player. Add check for player_entity:

```gdscript
if player_entity == null:
	issues.append("player_entity must be set")
```

---

### Task 5: Update CharacterSkin

**Files:**
- Modify: `player/characters/scripts/character_skin.gd`

- [ ] **Step 1: Remove IKTargets-related editor buttons**

The save/load marker buttons on CharacterSkin only saved `back_marker` position. Keep those if `back_marker` is still used, but remove any IKTargets-specific code.

Actually, `_save_markers_to_resource()` and `_load_markers_from_resource()` only handle `back_marker` (the back accessory marker). These are fine to keep — they're about the character, not IK. No changes needed to character_skin.gd.

---

### Task 6: Update Scene Files

**Files:**
- Modify: `player/player_entity.tscn`
- Modify: `player/characters/character_skin.tscn`
- Modify: `player/bikes/bike_skin.tscn`

These changes are best done in the **Godot editor** to avoid breaking node references. Steps:

- [ ] **Step 1: player_entity.tscn — Add IKTargets container**

In Godot editor with PlayerEntity scene open:
1. Select `VisualRoot` node
2. Add child → Node3D, name it `IKTargets`
3. Enable "Unique Name in Owner" on IKTargets

- [ ] **Step 2: player_entity.tscn — Move and rename proxy markers**

1. Select `LeftHandProxy` under VisualRoot → move under `IKTargets` → rename to `LeftHandTarget`
2. Select `RightHandProxy` under VisualRoot → move under `IKTargets` → rename to `RightHandTarget`
3. Select `LeftFootProxy` under VisualRoot → move under `IKTargets` → rename to `LeftFootTarget`
4. Select `RightFootProxy` under VisualRoot → move under `IKTargets` → rename to `RightFootTarget`
5. Enable "Unique Name in Owner" on each

- [ ] **Step 3: player_entity.tscn — Add new markers**

Under `IKTargets`, add Marker3D nodes:
1. `ButtTarget` — position at (0, 0.845, -0.195) (from mini_default seat_marker_position)
2. `ChestTarget` — position at (0, 1.147, -0.009) (from mini_default chest_position)
3. `HeadTarget` — position at (0, 1.751, -0.189) (from mini_default head_position)
4. `LeftArmMagnet` — position at (0.624, 1.074, -0.012)
5. `RightArmMagnet` — position at (-0.624, 1.074, -0.012)
6. `LeftLegMagnet` — position at (0.464, 0.569, 0.429)
7. `RightLegMagnet` — position at (-0.464, 0.569, 0.429)
8. Enable "Unique Name in Owner" on each

- [ ] **Step 4: player_entity.tscn — Wire @exports in inspector**

Select `PlayerEntity` root node → Inspector → IK Targets group:
- Wire each marker to the corresponding IKTargets child node

- [ ] **Step 5: player_entity.tscn — Update idle animation tracks**

The idle animation (sub_resource Animation) has tracks referencing `%LeftHandProxy:position` etc. Update track paths:
- `%LeftHandProxy:position` → `%LeftHandTarget:position`
- `%LeftHandProxy:rotation` → `%LeftHandTarget:rotation`
- `%LeftFootProxy:position` → `%LeftFootTarget:position`
- Also update ChestTarget and other tracks if referenced

- [ ] **Step 6: character_skin.tscn — Remove IKTargets**

1. Delete the `IKTargets` node (and all its children: LeftArmMagnet, RightArmMagnet, LeftLegMagnet, RightLegMagnet, ChestTarget, HeadTarget)
2. IKController's @export references will show as broken — this is expected since they were removed in Task 1

- [ ] **Step 7: bike_skin.tscn — Remove marker nodes**

Delete these nodes:
- `TrainingWheelsModsMarker`
- `SeatMarker`
- `LeftHandleBarMarker`
- `LeftPegMarker`
- `FrontWheelGroundMarker`
- `FrontWheelFrontMarker`
- `RearWheelGroundMarker`
- `RearWheelBackMarker`

Keep `MeshNode` — it stays.

---

### Task 7: Verify and Re-Author Poses

- [ ] **Step 1: Open PlayerEntity scene in editor**

1. Set `bike_definition` to `mini_default_skin_definition.tres`
2. Click "Init IK from Bike" on AnimationController
3. Verify rider IK pose looks correct on the mini bike
4. If not, adjust markers and click "Save Default Pose"

- [ ] **Step 2: Test sport bike**

1. Set `bike_definition` to `sport_default_skin_definition.tres`
2. Click "Init IK from Bike"
3. Rider pose will likely be wrong — adjust markers to fit the sport bike
4. Click "Save Default Pose" to save correct values to sport_default .tres

- [ ] **Step 3: Test naked bike**

Same as Step 2 but with `naked_default_skin_definition.tres`.

- [ ] **Step 4: Run the game**

1. Start game with each bike type
2. Verify: hands follow handlebars during steering, feet on pegs, rider leans correctly
3. Verify: idle animation plays, transitions back to riding smoothly
4. Verify: crash → ragdoll → respawn restores correct pose
5. Verify: multiplayer — remote players have correct poses

- [ ] **Step 5: Test bike switching**

If the customize menu allows bike switching:
1. Switch between bike types mid-game
2. Verify `update_skins()` correctly re-initializes IK with new bike's poses
