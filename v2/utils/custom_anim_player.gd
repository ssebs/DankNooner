class_name CustomAnimPlayer extends Node

## Lightweight, additive-blend animation runner for the rider pose pipeline.
## Each playing animation contributes a *delta from its t=0 keyframe* sample to a
## consumer's pose, scaled by the layer's blend weight. Multiple layers can run
## at once; weights fade in/out independently.
##
## Caller API mirrors AnimationPlayer where it makes sense (play/stop/play_backwards)
## but returns a Layer handle so you can read duration / time / weight without going
## through a name lookup.

const DEFAULT_FADE_SPEED := 4.0


class Layer:
	var anim: Animation
	var speed: float = 1.0  ## negative = backwards
	var time: float = 0.0
	var looping: bool = true
	## Non-loop only: if true, time clamps at the end and weight stays — caller must
	## stop() explicitly. If false, hitting an end auto-fades the layer out.
	var hold_at_end: bool = false
	var weight: float = 0.0
	var target_weight: float = 1.0
	var fade_speed: float = DEFAULT_FADE_SPEED
	var finished: bool = false  ## non-loop anim hit its end and faded out
	## Cached (node, property_path, track_idx) tuples for tracks not in the pose pipeline's
	## allowlist. Lazily filled on first apply_to_nodes() call so we don't re-walk per tick.
	var _extras_resolved: Variant = null

	func get_duration() -> float:
		return anim.length if anim else 0.0

	func get_time() -> float:
		return time

	func is_playing() -> bool:
		return not finished and (weight > 0.0 or target_weight > 0.0)


var _layers: Array[Layer] = []


## Start an animation. Returns the Layer handle (cache it to query time/duration or stop later).
func play(
	anim: Animation,
	speed: float = 1.0,
	looping: bool = true,
	fade_speed: float = DEFAULT_FADE_SPEED
) -> Layer:
	var layer := Layer.new()
	layer.anim = anim
	layer.speed = speed
	layer.looping = looping
	layer.fade_speed = fade_speed
	layer.target_weight = 1.0
	layer.time = 0.0 if speed >= 0.0 else anim.length
	_layers.append(layer)
	return layer


## Convenience — same as play() with negative speed and time starting at the end.
func play_backwards(
	anim: Animation,
	speed: float = 1.0,
	looping: bool = true,
	fade_speed: float = DEFAULT_FADE_SPEED
) -> Layer:
	return play(anim, -absf(speed), looping, fade_speed)


## Play once, hold the end pose at full weight until stop() is called.
## Use this for "settle into pose, stay there" anims like idle.
func play_one_shot(
	anim: Animation, speed: float = 1.0, fade_speed: float = DEFAULT_FADE_SPEED
) -> Layer:
	var layer := play(anim, speed, false, fade_speed)
	layer.hold_at_end = true
	return layer


## Fade out a layer. It is removed once weight reaches 0.
func stop(layer: Layer, fade_speed: float = DEFAULT_FADE_SPEED) -> void:
	layer.target_weight = 0.0
	layer.fade_speed = fade_speed


## Drop everything immediately, no fade.
func stop_all() -> void:
	_layers.clear()


func get_layers() -> Array[Layer]:
	return _layers


## Advance all layers by delta. Call this once per frame from the consumer
## (typically AnimationController._update_riding) BEFORE sampling.
func tick(delta: float) -> void:
	var i := 0
	while i < _layers.size():
		var layer := _layers[i]
		layer.weight = move_toward(layer.weight, layer.target_weight, layer.fade_speed * delta)
		layer.time += delta * layer.speed
		if layer.looping and layer.anim.length > 0.0:
			layer.time = fposmod(layer.time, layer.anim.length)
		else:
			# Non-loop: clamp at ends. Auto-fade only if hold_at_end is false.
			if layer.time >= layer.anim.length:
				layer.time = layer.anim.length
				if not layer.hold_at_end:
					layer.target_weight = 0.0
			elif layer.time <= 0.0:
				layer.time = 0.0
				if not layer.hold_at_end:
					layer.target_weight = 0.0

		if layer.weight <= 0.0 and layer.target_weight <= 0.0:
			layer.finished = true
			_layers.remove_at(i)
		else:
			i += 1


## For a given track path (e.g. "IKTargets/LeftHandTarget:position"), return the
## summed delta-from-default across all active layers, scaled by each layer's weight.
## Returns null if no layer animates this path. Use sample_vec3 / sample_xform helpers
## if you want a typed result with a fallback.
func sample(track_path: NodePath) -> Variant:
	var accum: Variant = null
	for layer in _layers:
		if layer.weight <= 0.0:
			continue
		var track_idx := layer.anim.find_track(track_path, Animation.TYPE_VALUE)
		if track_idx == -1:
			continue
		# value_track_interpolate ignores the track's enabled flag (only AnimationPlayer
		# honors it), so check it here — otherwise tracks toggled off in the editor still
		# leak deltas into the pose.
		if not layer.anim.track_is_enabled(track_idx):
			continue
		var sampled = layer.anim.value_track_interpolate(track_idx, layer.time)
		var base = layer.anim.value_track_interpolate(track_idx, 0.0)
		var delta_val = sampled - base
		if accum == null:
			accum = delta_val * layer.weight
		else:
			accum += delta_val * layer.weight
	return accum


## Typed sampling helpers — return Vector3.ZERO / Transform3D.IDENTITY when no layer
## touches the track, so callers can unconditionally add the result to their pose.
func sample_vec3(track_path: NodePath) -> Vector3:
	var v = sample(track_path)
	return v if v != null else Vector3.ZERO


func sample_float(track_path: NodePath) -> float:
	var v = sample(track_path)
	return v if v != null else 0.0


## Auto-apply raw track values for anything NOT in the pose pipeline's hardcoded allowlist.
## Lets animators drop new tracks (VFX emitting, particle positions, materials, etc.) into
## an animation and have them "just work" without touching this file or AnimationController.
##
## - `allowlist`: Dictionary of NodePath → bool for tracks the caller handles via additive deltas.
## - Resolution per track: base_node.get_node_or_null(path) → find_child(last_name, true, false).
## - Later layers overwrite earlier ones for the same track (matches add-order priority).
func apply_to_nodes(base_node: Node, allowlist: Dictionary) -> void:
	for layer in _layers:
		if layer.weight <= 0.0:
			continue
		if layer._extras_resolved == null:
			_resolve_layer_extras(layer, base_node, allowlist)
		for entry in layer._extras_resolved:
			var node: Node = entry[0]
			if not is_instance_valid(node):
				continue
			var value = layer.anim.value_track_interpolate(entry[2], layer.time)
			node.set_indexed(entry[1], value)


func _resolve_layer_extras(layer: Layer, base_node: Node, allowlist: Dictionary) -> void:
	layer._extras_resolved = []
	for i in layer.anim.get_track_count():
		if layer.anim.track_get_type(i) != Animation.TYPE_VALUE:
			continue
		if not layer.anim.track_is_enabled(i):
			continue
		var path := layer.anim.track_get_path(i)
		if allowlist.has(path):
			continue
		var path_str := String(path)
		var colon := path_str.find(":")
		var node_path := NodePath(path_str.substr(0, colon))
		var prop_path := NodePath(path_str.substr(colon))
		var node := base_node.get_node_or_null(node_path)
		if node == null:
			# Editor sometimes serializes paths that don't resolve from the anim's root_node
			# (e.g. a unique-name tracked node living elsewhere in the scene gets saved as a
			# sibling-relative path). Fall back to a recursive find by last component name.
			var parts := path_str.substr(0, colon).split("/")
			var leaf := String(parts[parts.size() - 1]).trim_prefix("%")
			node = base_node.find_child(leaf, true, false)
		if node == null:
			push_warning("CustomAnimPlayer: unresolved track path '%s'" % path)
			continue
		layer._extras_resolved.append([node, prop_path, i])
