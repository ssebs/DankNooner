@tool
class_name SkidmarkController extends Node

## Local-only skidmark VFX. Builds a ground-conforming ribbon mesh behind the
## rear wheel whenever the bike is drifting. Driven entirely by already-synced
## state (`movement_controller.is_drifting` + the rear ground raycast), so every
## client renders every player's marks with no RPC — same philosophy as the
## spark particles. Runs in `_process` (visual), NOT in the rollback tick:
## rollback re-simulates ticks and would duplicate/corrupt the geometry.

@export var player_entity: PlayerEntity
@export var movement_controller: MovementController

## Half the ribbon width, in meters.
@export var ribbon_half_width: float = 0.09
## Lift above the ground along the surface normal to avoid z-fighting.
@export var ground_offset: float = 0.02
## Minimum rear-wheel travel before a new strip segment is appended.
@export var min_segment_dist: float = 0.15
## Seconds a finished ribbon takes to fade out after the drift ends.
@export var fade_time: float = 4.0
## World length (meters) over which skidmarktex tiles once along the ribbon.
@export var tex_tile_length: float = 1.0
## Max ribbons kept per player before the oldest is recycled (bounds memory).
@export var max_ribbons: int = 12
## Max strip points in one ribbon before it is finalized and a new one starts.
@export var max_points: int = 256

const SKID_TEXTURE: Texture2D = preload("res://resources/textures/skidmarktex.png")

# Black ink opaque, white background transparent (luminance → alpha) so it works
# whether or not the PNG carries an alpha channel. `fade` drives the fade-out.
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;
uniform sampler2D tex : source_color;
uniform float fade = 1.0;
void fragment() {
	vec4 t = texture(tex, UV);
	float ink = 1.0 - dot(t.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = vec3(0.04);
	ALPHA = ink * t.a * fade;
}
"""

# Shared across all SkidmarkController instances — the shader is identical.
static var _shader: Shader

var _ribbons: Array[Skidmark] = []
var _active: Skidmark = null


## One ribbon = one continuous drift mark. Holds its world-space strip points
## plus its own material so it can fade independently.
class Skidmark:
	var node: MeshInstance3D
	var mesh: ImmediateMesh
	var mat: ShaderMaterial
	var left: PackedVector3Array = PackedVector3Array()
	var right: PackedVector3Array = PackedVector3Array()
	var vs: PackedFloat32Array = PackedFloat32Array()
	var last_center: Vector3
	var length_accum: float = 0.0
	var fading: bool = false
	var fade_elapsed: float = 0.0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if player_entity == null:
		warnings.append("player_entity is not assigned")
	if movement_controller == null:
		warnings.append("movement_controller is not assigned")
	return warnings


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_advance_fades(delta)

	if movement_controller.is_drifting:
		_extend_active()
	elif _active != null:
		_finalize_active()


## Append a strip segment at the rear wheel's current ground contact, if it has
## moved far enough since the last point.
func _extend_active() -> void:
	var rc := player_entity.rear_raycast
	# Drift requires the floor, but the raycast can briefly miss on crests.
	if not rc.is_colliding():
		return

	var normal := rc.get_collision_normal()
	var center := rc.get_collision_point() + normal * ground_offset

	if _active == null:
		_active = _new_ribbon()
		_active.last_center = center
		return

	var travel := center - _active.last_center
	var seg_len := travel.length()
	if seg_len < min_segment_dist:
		return
	travel /= seg_len
	var side := travel.cross(normal).normalized() * ribbon_half_width

	# Seed the strip's first point pair at the previous center so the very first
	# segment is a full quad, not a degenerate triangle.
	if _active.left.is_empty():
		_active.left.append(_active.last_center - side)
		_active.right.append(_active.last_center + side)
		_active.vs.append(0.0)

	_active.length_accum += seg_len
	_active.left.append(center - side)
	_active.right.append(center + side)
	_active.vs.append(_active.length_accum / tex_tile_length)
	_active.last_center = center

	_rebuild(_active)

	if _active.left.size() >= max_points:
		_finalize_active()


## Rebuild a ribbon's triangle-strip geometry from its world-space point pairs.
func _rebuild(rib: Skidmark) -> void:
	if rib.left.size() < 2:
		return
	rib.mesh.clear_surfaces()
	rib.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in rib.left.size():
		rib.mesh.surface_set_uv(Vector2(0.0, rib.vs[i]))
		rib.mesh.surface_add_vertex(rib.left[i])
		rib.mesh.surface_set_uv(Vector2(1.0, rib.vs[i]))
		rib.mesh.surface_add_vertex(rib.right[i])
	rib.mesh.surface_end()


func _new_ribbon() -> Skidmark:
	var rib := Skidmark.new()
	rib.mesh = ImmediateMesh.new()
	rib.mat = ShaderMaterial.new()
	rib.mat.shader = _get_shader()
	rib.mat.set_shader_parameter("tex", SKID_TEXTURE)
	rib.mat.set_shader_parameter("fade", 1.0)
	rib.node = MeshInstance3D.new()
	rib.node.mesh = rib.mesh
	rib.node.material_override = rib.mat
	# Vertices are authored in world space — ignore the parent's transform.
	rib.node.top_level = true
	rib.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Parent to the level (player's parent) so marks persist where they were laid
	# and clear on level reload.
	player_entity.get_parent().add_child(rib.node)

	_ribbons.append(rib)
	_enforce_cap()
	return rib


## Recycle the oldest ribbons once this player exceeds its budget.
func _enforce_cap() -> void:
	while _ribbons.size() > max_ribbons:
		var old: Skidmark = _ribbons.pop_front()
		if old == _active:
			_active = null
		old.node.queue_free()


func _finalize_active() -> void:
	_active.fading = true
	_active = null


## Advance fade-out on finalized ribbons and free them once invisible.
func _advance_fades(delta: float) -> void:
	for i in range(_ribbons.size() - 1, -1, -1):
		var rib := _ribbons[i]
		if not rib.fading:
			continue
		rib.fade_elapsed += delta
		var f := 1.0 - rib.fade_elapsed / fade_time
		if f <= 0.0:
			rib.node.queue_free()
			_ribbons.remove_at(i)
		else:
			rib.mat.set_shader_parameter("fade", f)


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader
