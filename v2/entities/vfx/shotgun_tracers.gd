## Shotgun pellet streaks from this node (the muzzle) to the far end of the shotgun's hitbox, so
## what you see reaches exactly as far as the shot does. Cosmetic: each peer rolls its own spread;
## only a hit's position comes from the server.
class_name ShotgunTracers extends Node3D

## The shooter's GunCollisionShape: a box whose local -Y points down the barrel.
@export var hitbox: CollisionShape3D
@export var pellet_count: int = 6
## Seconds a streak takes to grow from the barrel out to its end.
@export var travel_time: float = 0.25
## Seconds a full-length streak takes to fade out.
@export var lifetime: float = 0.25
@export var thickness: float = 0.06
@export var color: Color = Color(1.0, 0.85, 0.4)
## Emission strength; past 1 it blooms in levels with glow on.
@export var glow_energy: float = 1.5


## One streak lands on hit_pos when the shot hit someone; the rest spread across the hitbox's far
## end (its full width, a quarter of its height), so the spread you see is the spread that hits.
func fire(has_hit: bool, hit_pos: Vector3) -> void:
	var box := hitbox.shape as BoxShape3D
	for i in pellet_count:
		# hit_pos is the target's origin, at its wheels; raise it to the hitbox's height
		var end := hit_pos + Vector3.UP * hitbox.position.y
		if !has_hit or i > 0:
			var far := Vector3(
				randf_range(-0.5, 0.5) * box.size.x,
				-box.size.y * 0.5,
				randf_range(-0.125, 0.125) * box.size.z
			)
			end = hitbox.global_transform * far
		_spawn_tracer(global_position, end)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow_energy
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, from.distance_to(to))
	mesh.material = material
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Not under the gun: it hides on unequip, and the streak must not ride along with the bike
	get_tree().current_scene.add_child(tracer)
	tracer.look_at_from_position(from, to)
	_grow(0.0, tracer, from, to)
	var tween := tracer.create_tween()
	tween.tween_method(_grow.bind(tracer, from, to), 0.0, 1.0, travel_time)
	tween.tween_property(material, "albedo_color:a", 0.0, lifetime)
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, lifetime)
	tween.tween_callback(tracer.queue_free)


## The box is centred on its node, so the node rides the midpoint of the grown part.
func _grow(t: float, tracer: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	tracer.scale = Vector3(1.0, 1.0, maxf(t, 0.001))
	tracer.global_position = from.lerp(to, t * 0.5)
