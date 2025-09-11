class_name UI extends MarginContainer

@export var notify_time_sec = 5

@onready var angle_label: Label = %AngleLabel
@onready var notify_label: Label = %NotifyLabel
@onready var throttle_progress: ProgressBar = %ThrottleProgress

# var notifications = [] # todo: use queue for multiple

func _ready():
    SignalBus.angle_updated.connect(on_angle_updated)
    SignalBus.notify_ui.connect(on_notify_ui)
    SignalBus.throttle_updated.connect(on_throttle_updated)
    
    notify_label.text = ""
    throttle_progress.value = 0

func on_throttle_updated(pct: float):
    throttle_progress.value = pct

func on_angle_updated(angle_deg: float):
    angle_label.text = "%.0f°" % abs(angle_deg)

func on_notify_ui(msg: String):
    notify_label.text = msg
    await get_tree().create_timer(notify_time_sec).timeout
    notify_label.text = ""
