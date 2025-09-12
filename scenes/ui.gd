class_name UI extends MarginContainer

@export var notify_time_sec = 5

@onready var angle_label: Label = %AngleLabel
@onready var notify_label: Label = %NotifyLabel
@onready var score_label: Label = %ScoreLabel
@onready var distance_label: Label = %DistanceLabel
@onready var throttle_progress: ProgressBar = %ThrottleProgress

@onready var game_panel: Control = %GamePanel
@onready var main_menu_panel: Control = %MainMenuPanel
@onready var pause_menu_panel: Control = %PauseMenuPanel

@onready var play_btn: Button = %PlayBtn
@onready var quit_btn: Button = %QuitBtn
@onready var volume_slider: Slider = %VolumeSlider

# var notifications = [] # todo: use queue for multiple

func _ready():
    SignalBus.angle_updated.connect(on_angle_updated)
    SignalBus.notify_ui.connect(on_notify_ui)
    SignalBus.throttle_updated.connect(on_throttle_updated)
    SignalBus.score_updated.connect(on_score_updated)
    SignalBus.distance_updated.connect(on_distance_updated)
    
    notify_label.text = ""
    score_label.text = "0"
    distance_label.text = "0m"
    throttle_progress.value = 0

func switch_panels(state: MainGame.GameState):
    match state:
        MainGame.GameState.MAIN_MENU:
            game_panel.visible = false
            pause_menu_panel.visible = false
            main_menu_panel.visible = true
        MainGame.GameState.PLAYING:
            game_panel.visible = true
            pause_menu_panel.visible = false
            main_menu_panel.visible = false
        MainGame.GameState.PAUSE_MENU:
            game_panel.visible = false
            pause_menu_panel.visible = true
            main_menu_panel.visible = false

#region signal handlers
func on_throttle_updated(pct: float):
    throttle_progress.value = pct

func on_score_updated(score: int):
    score_label.text = "Score: %.0f" % score

func on_distance_updated(distance: int):
    distance_label.text = "Distance: %dm" % distance

func on_angle_updated(angle_deg: float):
    angle_label.text = "%.0f°" % abs(angle_deg)

    var color: Color
    if angle_deg <= 45:
        # From white (0°) to yellow (45°)
        var t = angle_deg / 45.0
        color = Color.WHITE.lerp(Color.YELLOW, t)
    else:
        # From yellow (45°) to red (90°)
        var t = (angle_deg - 45.0) / 45.0
        color = Color.YELLOW.lerp(Color.RED, t)


    angle_label.add_theme_color_override("font_color", color)

func on_notify_ui(msg: String):
    notify_label.text = msg
    await get_tree().create_timer(notify_time_sec).timeout
    notify_label.text = ""
#endregion