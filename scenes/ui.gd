class_name UI extends MarginContainer

@export var notify_time_sec = 5

@onready var angle_label: Label = $AngleLabel
@onready var notify_label: Label = $NotifyLabel

# var notifications = [] # todo: use queue for multiple

func _ready():
    SignalBus.angle_updated.connect(on_angle_updated)
    SignalBus.notify_ui.connect(on_notify_ui)
    
    notify_label.text = ""


func on_angle_updated(angle_deg: float):
    angle_label.text = "%.0f°" % abs(angle_deg)

func on_notify_ui(msg: String):
    notify_label.text = msg
    await get_tree().create_timer(notify_time_sec).timeout
    notify_label.text = ""
