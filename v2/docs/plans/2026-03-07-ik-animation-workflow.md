# IK Animation Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add editor tool buttons to `AnimationController` so trick animations can be authored from `player_entity.tscn` with the character correctly posed on the bike.

**Architecture:** Three tool buttons on `AnimationController` handle the full workflow: derive IK target positions from the bike's attachment markers, save the refined pose as a `"default_pose"` animation in `IK_anim_lib.res`, and reset to that pose before authoring each new animation. Making `CharacterSkin` editable in `player_entity.tscn` exposes the `IKAnimationPlayer` and IK target markers for direct manipulation in the viewport.

**Tech Stack:** Godot 4.6, GDScript, `@export_tool_button`, `AnimationPlayer`, `AnimationLibrary`, `ResourceSaver`

---

### Task 1: Make CharacterSkin editable in player_entity.tscn

Exposes `IKAnimationPlayer` and IK target markers from within `player_entity.tscn`.

**Files:**
- Modify: `entities/player/player_entity.tscn` (bottom of file)

**Step 1: Add editable path**

At the bottom of `player_entity.tscn`, alongside the existing editable paths, add:

```
[editable path="VisualRoot/CharacterSkin"]
```

**Step 2: Verify in editor**

Open `player_entity.tscn`. Expand `VisualRoot > CharacterSkin` in the scene tree. You should now be able to select `IKAnimationPlayer` and the `IKTargets/*` markers as if they were part of this scene.

**Step 3: Commit**

```bash
git add entities/player/player_entity.tscn
git commit -m "feat: make CharacterSkin editable in player_entity for animation authoring"
```

---

### Task 2: Add "Init IK from Bike" tool button to AnimationController

Sets all IK target positions from the bike's attachment markers - the starting point for any animation.

**Files:**
- Modify: `entities/player/controllers/animation_controller.gd`

**Step 1: Add the tool button export and function**

After the existing `@export` block (around line 18), add the button declaration:

```gdscript
@export_tool_button("Init IK from Bike") var _init_ik_btn = _editor_init_ik_from_bike
```

Then add the function before `_ready()`:

```gdscript
func _editor_init_ik_from_bike() -> void:
	if bike_skin == null or character_skin == null:
		printerr("AnimationController: bike_skin and character_skin must be set")
		return
	var def = bike_skin.skin_definition
	character_skin.set_ik_targets_for_bike(
		def.seat_marker_position,
		def.left_handlebar_marker_position,
		def.left_peg_marker_position
	)
	character_skin.enable_ik()
```

**Step 2: Verify in editor**

Open `player_entity.tscn`. Select `AnimationController` in the scene tree. Click "Init IK from Bike" in the Inspector. The character should visibly shift to sit on the bike with hands near handlebars and feet near pegs.

**Step 3: Commit**

```bash
git add entities/player/controllers/animation_controller.gd
git commit -m "feat: add Init IK from Bike tool button to AnimationController"
```

---

### Task 3: Add "Save Default Pose" tool button to AnimationController

Captures all IK target marker transforms (position + rotation) and writes them as keyframe 0 of a `"default_pose"` animation in `IK_anim_lib.res`.

**Files:**
- Modify: `entities/player/controllers/animation_controller.gd`

**Step 1: Add the tool button export**

After the "Init IK from Bike" button line, add:

```gdscript
@export_tool_button("Save Default Pose") var _save_pose_btn = _editor_save_default_pose
```

**Step 2: Add the function**

```gdscript
func _editor_save_default_pose() -> void:
	var ik_ctrl = character_skin.ik_controller
	var anim_player = character_skin.ik_anim_player
	if ik_ctrl == null or anim_player == null:
		printerr("AnimationController: missing ik_controller or ik_anim_player")
		return

	var lib_name = "IK_anim_lib"
	var anim_name = "default_pose"

	if not anim_player.has_animation_library(lib_name):
		printerr("AnimationController: animation library '%s' not found" % lib_name)
		return

	var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
	if not lib.has_animation(anim_name):
		lib.add_animation(anim_name, Animation.new())
	var anim: Animation = lib.get_animation(anim_name)
	anim.clear()
	anim.length = 0.1

	# Map of node path (relative to CharacterSkin) -> marker node
	var markers := {
		"IKTargets/ButtPosition": ik_ctrl.butt_pos,
		"IKTargets/ChestTarget": ik_ctrl.ik_chest,
		"IKTargets/HeadTarget": ik_ctrl.ik_head,
		"IKTargets/LeftHand": ik_ctrl.ik_left_hand,
		"IKTargets/RightHand": ik_ctrl.ik_right_hand,
		"IKTargets/LeftArmMagnet": ik_ctrl.ik_left_arm_magnet,
		"IKTargets/RightArmMagnet": ik_ctrl.ik_right_arm_magnet,
		"IKTargets/LeftFoot": ik_ctrl.ik_left_foot,
		"IKTargets/RightFoot": ik_ctrl.ik_right_foot,
		"IKTargets/LeftLegMagnet": ik_ctrl.ik_left_leg_magnet,
		"IKTargets/RightLegMagnet": ik_ctrl.ik_right_leg_magnet,
	}

	for node_path in markers:
		var marker: Marker3D = markers[node_path]
		_keyframe_marker(anim, node_path, marker)

	var err = ResourceSaver.save(lib)
	if err == OK:
		print("AnimationController: Saved default_pose to IK_anim_lib.res")
	else:
		printerr("AnimationController: Failed to save IK_anim_lib.res, error: ", err)


func _keyframe_marker(anim: Animation, node_path: String, marker: Marker3D) -> void:
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, node_path + ":position")
	anim.track_insert_key(pos_track, 0.0, marker.position)

	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, node_path + ":rotation")
	anim.track_insert_key(rot_track, 0.0, marker.rotation)
```

**Step 3: Verify in editor**

1. Click "Init IK from Bike" to place the character
2. Manually rotate a marker (e.g. `LeftHand`) to grip the handlebar properly
3. Click "Save Default Pose"
4. Check the Output panel - should print "Saved default_pose to IK_anim_lib.res"
5. Open `IKAnimationPlayer` in the AnimationPlayer panel - a `"IK_anim_lib/default_pose"` animation should exist with position/rotation tracks for all 11 markers

**Step 4: Commit**

```bash
git add entities/player/controllers/animation_controller.gd
git commit -m "feat: add Save Default Pose tool button to AnimationController"
```

---

### Task 4: Add "Reset to Default Pose" tool button to AnimationController

Restores all IK target markers to the saved `default_pose`, ready to start authoring a new animation.

**Files:**
- Modify: `entities/player/controllers/animation_controller.gd`

**Step 1: Add the tool button export**

After the "Save Default Pose" button line, add:

```gdscript
@export_tool_button("Reset to Default Pose") var _reset_pose_btn = _editor_reset_to_default_pose
```

**Step 2: Add the function**

```gdscript
func _editor_reset_to_default_pose() -> void:
	var anim_player = character_skin.ik_anim_player
	if anim_player == null:
		printerr("AnimationController: missing ik_anim_player")
		return
	var full_name = "IK_anim_lib/default_pose"
	if not anim_player.has_animation(full_name):
		printerr("AnimationController: no default_pose saved - run Save Default Pose first")
		return
	anim_player.play(full_name)
	anim_player.seek(0.0, true)
	anim_player.stop()
```

**Step 3: Verify in editor**

1. Move some IK markers around to mess up the pose
2. Click "Reset to Default Pose"
3. All markers should snap back to the saved default_pose positions/rotations

**Step 4: Commit**

```bash
git add entities/player/controllers/animation_controller.gd
git commit -m "feat: add Reset to Default Pose tool button to AnimationController"
```

---

### Task 5: Update AnimationController.md

Document the new editor workflow so it's findable.

**Files:**
- Modify: `planning_docs/AnimationController.md`

**Step 1: Add an Editor Workflow section**

Add after the existing "Animation Workflow Summary" section:

```markdown
## Editor Workflow (Authoring from player_entity.tscn)

Open `player_entity.tscn` to author animations with the character on the bike.

### Setup (once per bike)
1. Select `AnimationController` in the scene tree
2. Click **"Init IK from Bike"** — positions IK targets from the bike's attachment markers
3. Manually adjust marker rotations in the viewport (grip angle, foot angle, etc.)
4. Click **"Save Default Pose"** — saves position + rotation of all 11 IK targets as `"default_pose"` in `IK_anim_lib.res`

### Authoring each animation
1. Click **"Reset to Default Pose"** — restores markers to the saved base
2. Select `IKAnimationPlayer` and create/open an animation
3. Move/rotate IK target markers in the viewport
4. Keyframe `position` and `rotation` tracks for changed markers
5. Animations are bike-agnostic — positions are derived from the current bike's markers at runtime
```

**Step 2: Commit**

```bash
git add planning_docs/AnimationController.md
git commit -m "docs: add editor animation workflow to AnimationController.md"
```
