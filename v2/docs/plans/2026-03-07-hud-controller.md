# HUDController Debug HUD Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the Debug HUD from `player_entity.gd` into `HUDController` with `@export var` property setters that auto-update UI nodes.

**Architecture:** HUDController owns all debug UI nodes. PlayerEntity pushes state to HUDController via `@export var` setters in `_process`. HUDController toggled visible via `show_hud()`/`hide_hud()`.

**Tech Stack:** Godot 4.6, GDScript, `@tool`, `@export var` with `set(v)` pattern (see `graybox_staticbody.gd` for reference).

---

### Task 1: Add UI nodes to hud_controller.tscn

**Files:**
- Modify: `entities/player/controllers/hud_controller.tscn`

**Step 1: Replace scene content**

Open `entities/player/controllers/hud_controller.tscn` and replace with:

```
[gd_scene format=3 uid="uid://dvkip6up3p1qg"]

[ext_resource type="Script" uid="uid://civ7dg4q23qwd" path="res://entities/player/controllers/hud_controller.gd" id="1_bxvjo"]

[node name="HUDController" type="Control" unique_id=2128080993]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_bxvjo")

[node name="VBoxContainer" type="VBoxContainer" parent="."]
layout_mode = 1
offset_left = 16.0
offset_top = 16.0
offset_right = 250.0
offset_bottom = 400.0
theme_override_constants/separation = 4

[node name="SpeedLabel" type="Label" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
text = "Speed: 0"

[node name="GearLabel" type="Label" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
text = "Gear: 1"

[node name="RPMLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "RPM"

[node name="RPMBar" type="ProgressBar" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
custom_minimum_size = Vector2(200, 20)
max_value = 1.0
step = 0.01
show_percentage = false

[node name="ThrottleLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "Throttle"

[node name="ThrottleBar" type="ProgressBar" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
custom_minimum_size = Vector2(200, 20)
max_value = 1.0
step = 0.01
show_percentage = false

[node name="ClutchLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "Clutch"

[node name="ClutchBar" type="ProgressBar" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
custom_minimum_size = Vector2(200, 20)
max_value = 1.0
step = 0.01
show_percentage = false

[node name="GripLabel" type="Label" parent="VBoxContainer"]
layout_mode = 2
text = "Brake Danger"

[node name="GripBar" type="ProgressBar" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
custom_minimum_size = Vector2(200, 20)
max_value = 1.0
step = 0.01
show_percentage = false

[node name="TrickLabel" type="Label" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
visible = false
text = ""

[node name="BoostLabel" type="Label" parent="VBoxContainer" unique_name_in_owner=true]
layout_mode = 2
text = "Boost: 2"
```

**Step 2: Verify in Godot editor**

Open the scene in Godot — confirm all nodes appear in the scene tree with unique names (blue icon) on SpeedLabel, GearLabel, RPMBar, ThrottleBar, ClutchBar, GripBar, TrickLabel, BoostLabel.

**Step 3: Commit**

```bash
git add entities/player/controllers/hud_controller.tscn
git commit -m "feat: add debug HUD UI nodes to hud_controller.tscn"
```

---

### Task 2: Implement hud_controller.gd

**Files:**
- Modify: `entities/player/controllers/hud_controller.gd`

**Step 1: Replace file content**

```gdscript
@tool
class_name HUDController extends Control

@export var player_entity: PlayerEntity

@onready var _speed_label: Label = %SpeedLabel
@onready var _gear_label: Label = %GearLabel
@onready var _rpm_bar: ProgressBar = %RPMBar
@onready var _throttle_bar: ProgressBar = %ThrottleBar
@onready var _clutch_bar: ProgressBar = %ClutchBar
@onready var _grip_bar: ProgressBar = %GripBar
@onready var _trick_label: Label = %TrickLabel
@onready var _boost_label: Label = %BoostLabel

@export var speed: float = 0.0:
	set(v):
		speed = v
		_update_speed_label()

@export var current_gear: int = 1:
	set(v):
		current_gear = v
		_update_gear_label()

@export var is_stalled: bool = false:
	set(v):
		is_stalled = v
		_update_gear_label()

@export var rpm_ratio: float = 0.0:
	set(v):
		rpm_ratio = v
		_update_rpm_bar()

@export var throttle: float = 0.0:
	set(v):
		throttle = v
		_update_throttle_bar()

@export var clutch_value: float = 0.0:
	set(v):
		clutch_value = v
		_update_clutch_bar()

@export var grip_usage: float = 0.0:
	set(v):
		grip_usage = v
		_update_grip_bar()

@export var last_trick: int = 0:
	set(v):
		last_trick = v
		_update_trick_label()

@export var boost_count: int = 2:
	set(v):
		boost_count = v
		_update_boost_label()

@export var is_boosting: bool = false:
	set(v):
		is_boosting = v
		_update_boost_label()

@export var is_crashed: bool = false:
	set(v):
		is_crashed = v
		_update_speed_label()


func show_hud() -> void:
	visible = true


func hide_hud() -> void:
	visible = false


func _update_speed_label() -> void:
	if not is_node_ready():
		return
	if is_crashed:
		_speed_label.text = "CRASHED - Respawning..."
	else:
		_speed_label.text = "Speed: %d" % int(speed)


func _update_gear_label() -> void:
	if not is_node_ready():
		return
	if is_stalled:
		_gear_label.text = "STALLED - Gear: %d" % current_gear
	else:
		_gear_label.text = "Gear: %d" % current_gear


func _update_rpm_bar() -> void:
	if not is_node_ready():
		return
	_rpm_bar.value = rpm_ratio
	if rpm_ratio > 0.9:
		_rpm_bar.modulate = Color(1.0, 0.2, 0.2)
	elif rpm_ratio > 0.7:
		_rpm_bar.modulate = Color(1.0, 0.8, 0.2)
	else:
		_rpm_bar.modulate = Color(0.2, 0.6, 1.0)


func _update_throttle_bar() -> void:
	if not is_node_ready():
		return
	_throttle_bar.value = throttle
	if throttle > 0.9:
		_throttle_bar.modulate = Color(1.0, 0.2, 0.2)
	else:
		_throttle_bar.modulate = Color(0.2, 0.8, 0.2)


func _update_clutch_bar() -> void:
	if not is_node_ready():
		return
	_clutch_bar.value = clutch_value
	_clutch_bar.modulate = Color(0.8, 0.6, 0.2)


func _update_grip_bar() -> void:
	if not is_node_ready():
		return
	_grip_bar.value = grip_usage
	if grip_usage > 0.8:
		_grip_bar.modulate = Color(1.0, 0.1, 0.1)
	elif grip_usage > 0.5:
		_grip_bar.modulate = Color(1.0, 0.6, 0.0)
	else:
		_grip_bar.modulate = Color(0.2, 0.8, 0.2)


func _update_trick_label() -> void:
	if not is_node_ready():
		return
	# TrickController.Trick enum: 0 = NONE
	if last_trick != 0:
		_trick_label.text = TrickController.Trick.keys()[last_trick]
		_trick_label.visible = true
	else:
		_trick_label.visible = false


func _update_boost_label() -> void:
	if not is_node_ready():
		return
	_boost_label.text = "Boost: %d" % boost_count
	if is_boosting:
		_boost_label.text += " [ACTIVE]"
		_boost_label.modulate = Color(1.0, 0.8, 0.0)
	else:
		_boost_label.modulate = Color.WHITE
```

**Step 2: Verify no script errors in Godot**

Open Godot, check Output panel for errors on hud_controller.gd. Confirm @onready refs resolve (no null errors in editor).

**Step 3: Commit**

```bash
git add entities/player/controllers/hud_controller.gd
git commit -m "feat: implement HUDController with setter vars and update funcs"
```

---

### Task 3: Update player_entity.gd

**Files:**
- Modify: `entities/player/player_entity.gd`

**Step 1: Remove `_debug_*` var declarations (lines ~55-62)**

Delete these lines:
```gdscript
# Debug HUD elements
var _debug_speed_label: Label
var _debug_gear_label: Label
var _debug_rpm_bar: ProgressBar
var _debug_throttle_bar: ProgressBar
var _debug_clutch_bar: ProgressBar
var _debug_grip_bar: ProgressBar
var _debug_trick_label: Label
var _debug_boost_label: Label
```

**Step 2: Remove entire `#region Debug HUD` block (lines ~182-314)**

Delete from `#region Debug HUD` to `#endregion` (the entire commented-out block).

**Step 3: Update `_deferred_init` to show/hide HUD**

Replace the existing `_deferred_init` body:
```gdscript
func _deferred_init():
	if int(name) == multiplayer.get_unique_id():
		is_local_client = true
		camera_controller.switch_to_tps_cam()
		_init_input_handlers()
		if hud_controller:
			hud_controller.show_hud()
		_init_audio()
	else:
		camera_controller.disable_cameras()
		if hud_controller:
			hud_controller.hide_hud()
```

**Step 4: Add `_process` to push state to HUDController**

Add after `_rollback_tick`:
```gdscript
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_local_client or hud_controller == null:
		return
	hud_controller.speed = speed
	hud_controller.current_gear = current_gear
	hud_controller.is_stalled = gearing_controller.is_stalled if gearing_controller else false
	hud_controller.rpm_ratio = rpm_ratio
	hud_controller.throttle = input_controller.throttle if input_controller else 0.0
	hud_controller.clutch_value = clutch_value
	hud_controller.grip_usage = grip_usage
	hud_controller.last_trick = trick_controller._last_trick if trick_controller else 0
	hud_controller.boost_count = boost_count
	hud_controller.is_boosting = is_boosting
	hud_controller.is_crashed = is_crashed
```

**Step 5: Verify no script errors in Godot**

Check Output panel. Run game and confirm debug HUD appears for local player with live-updating values.

**Step 6: Commit**

```bash
git add entities/player/player_entity.gd
git commit -m "refactor: move debug HUD logic from PlayerEntity to HUDController"
```
