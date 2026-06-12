## Base class for level-authored objects that gamemodes (tutorial, race, etc.) can
## reference, activate, and react to. Dumb props — they emit signals, expose
## activate/deactivate, but never decide gamemode completion themselves.
##
## If a child Area3D exists, body_entered/body_exited are auto-wired to
## the entered/exited signals (filtered to PlayerEntity).
class_name GameModeObject extends Node3D

signal entered(player: PlayerEntity)
signal exited(player: PlayerEntity)
signal hit(player: PlayerEntity)

@export var is_active: bool = true:
	set(value):
		is_active = value
		_apply_active_state()


func _ready():
	var area := get_node_or_null("Area3D") as Area3D
	if area:
		area.body_entered.connect(_on_area_body_entered)
		area.body_exited.connect(_on_area_body_exited)
	_apply_active_state()


func activate():
	is_active = true


func deactivate():
	is_active = false


func _apply_active_state():
	visible = is_active
	var area := get_node_or_null("Area3D") as Area3D
	if area:
		area.monitoring = is_active
	# Also kill solid collision (e.g. checkpoint pillars) so a hidden object
	# isn't an invisible wall. Recurses so nested StaticBody3D shapes are caught.
	_set_collision_disabled(self, not is_active)


func _set_collision_disabled(node: Node, disabled: bool):
	for child in node.get_children():
		if child is CollisionShape3D:
			child.disabled = disabled
		_set_collision_disabled(child, disabled)


func _on_area_body_entered(body: Node3D):
	if !is_active:
		return
	if body is PlayerEntity:
		entered.emit(body)


func _on_area_body_exited(body: Node3D):
	if !is_active:
		return
	if body is PlayerEntity:
		exited.emit(body)
