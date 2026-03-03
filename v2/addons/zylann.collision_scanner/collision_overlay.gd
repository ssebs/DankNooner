@tool
extends Control

const BASE_CELL_SIZE = 8
const RAY_LENGTH = 4000.0
const FRAME_TIME_BUDGET_MS = 6

@onready var _texture_rect := $TextureRect as TextureRect

var _image: Image
var _texture: ImageTexture
var _cell_x := 0
var _cell_y := 0
var _cell_size := BASE_CELL_SIZE
var _done := false
var _camera: Camera3D
var _prev_camera_transform: Transform3D


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_physics_process(false)


func set_camera(camera: Camera3D) -> void:
	assert(camera != null)
	if camera != _camera:
		print("Setting new camera")
		_camera = camera
		_prev_camera_transform = _camera.global_transform
		_restart()


func _reset() -> void:
	set_physics_process(false)
	if _texture_rect == null:
		return
	if size.x == 0 or size.y == 0:
		print("Invalid size ", size)
		return
	_cell_x = 0
	_cell_y = 0
	_cell_size = BASE_CELL_SIZE
	var size_i := Vector2i(int(size.x), int(size.y))
	if _image == null or _image.get_size() != size_i:
		print("Creating image ", size_i)
		_image = Image.create_empty(size_i.x, size_i.y, false, Image.FORMAT_RGB8)
	_image.fill(Color(0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	_texture_rect.texture = _texture
	_done = false


func _restart() -> void:
	_reset()
	set_physics_process(true)


func _notification(what: int) -> void:
	if _is_in_edited_scene(self):
		return

	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if is_visible_in_tree():
				_restart()
			else:
				_reset()

		NOTIFICATION_RESIZED:
			_restart()


func _process(_delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _camera.global_transform != _prev_camera_transform:
		_prev_camera_transform = _camera.global_transform
		_restart()
		return


func _physics_process(_delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		print("Camera is null, stopping")
		_camera = null
		set_physics_process(false)
		return

	var world := _camera.get_world_3d()
	var space_state := world.direct_space_state

	var cell_count_x := _image.get_width() / _cell_size
	var cell_count_y := _image.get_height() / _cell_size

	var time_before := Time.get_ticks_msec()

	while (not _done) and (Time.get_ticks_msec() - time_before) < FRAME_TIME_BUDGET_MS:
		var pixel_pos := (Vector2(_cell_x + 0.5, _cell_y + 0.5) * _cell_size).floor()
		var ray_origin := _camera.project_ray_origin(pixel_pos)
		var ray_dir := _camera.project_ray_normal(pixel_pos)

		var color := Color(0, 0, 0)

		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * RAY_LENGTH)
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			var n: Vector3 = 0.5 * hit.normal + Vector3(0.5, 0.5, 0.5)
			color = Color(n.x, n.y, n.z, 1.0)

		_plot(_image, _cell_x, _cell_y, _cell_size, color)

		var done_row := false
		var prev_cell_y := _cell_y
		var prev_cell_size := _cell_size

		_cell_x += 1
		if _cell_x >= cell_count_x:
			_cell_x = 0
			_cell_y += 1
			done_row = true

			if _cell_y >= cell_count_y:
				if _cell_size > 1:
					_cell_y = 0
					_cell_size /= 2
					cell_count_x = _image.get_width() / _cell_size
					cell_count_y = _image.get_height() / _cell_size
				else:
					_done = true

		if done_row:
			# Update the texture with the new image data
			_texture.update(_image)

	if _done:
		print("Done")
		set_physics_process(false)


static func _plot(im: Image, cx: int, cy: int, cell_size: int, color: Color) -> void:
	if cell_size == 1:
		im.set_pixel(cx, cy, color)

	elif cell_size == 2:
		var x := cx * 2
		var y := cy * 2
		im.set_pixel(x, y, color)
		var ok_x := x + 1 < im.get_width()
		var ok_y := y + 1 < im.get_height()
		if ok_x:
			im.set_pixel(x + 1, y, color)
		if ok_y:
			im.set_pixel(x, y + 1, color)
		if ok_x and ok_y:
			im.set_pixel(x + 1, y + 1, color)

	else:
		var cx_min := cx * cell_size
		var cy_min := cy * cell_size
		var cx_max := cx_min + cell_size
		var cy_max := cy_min + cell_size
		if cx_max >= im.get_width():
			cx_max = im.get_width()
		if cy_max >= im.get_height():
			cy_max = im.get_height()
		for y in range(cy_min, cy_max):
			for x in range(cx_min, cx_max):
				im.set_pixel(x, y, color)


static func _is_in_edited_scene(node: Node) -> bool:
	if not node.is_inside_tree():
		return false
	var edited_scene := node.get_tree().edited_scene_root
	if node == edited_scene:
		return true
	return edited_scene != null and edited_scene.is_ancestor_of(node)
