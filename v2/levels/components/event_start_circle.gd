class_name EventStartCircle extends Area3D

signal entered_event(peer_id: int)
signal exited_event(peer_id: int)


func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_exited(body: Node3D):
	if !body is PlayerEntity:
		return
	print(body.name + " exited start circle")
	exited_event.emit(body.name)


func _on_body_entered(body: Node3D):
	if !body is PlayerEntity:
		return
	print(body.name + " entered start circle")
	entered_event.emit(body.name)
