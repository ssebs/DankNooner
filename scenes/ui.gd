class_name UI extends MarginContainer

signal notify_finished()

@export var notify_time_sec = 3

@onready var angle_label: Label = %AngleLabel
@onready var notify_label: Label = %NotifyLabel
@onready var score_label: Label = %ScoreLabel
@onready var distance_label: Label = %DistanceLabel
@onready var max_score_label: Label = %MaxScoreLabel
@onready var max_distance_label: Label = %MaxDistanceLabel
@onready var max_clean_runs_label: Label = %MaxCleanRunsLabel
@onready var throttle_progress: ProgressBar = %ThrottleProgress

@onready var game_panel: Control = %GamePanel
@onready var main_menu_panel: Control = %MainMenuPanel
@onready var pause_menu_panel: Control = %PauseMenuPanel

@onready var play_btn: Button = %PlayBtn
@onready var quit_btn: Button = %QuitBtn
@onready var volume_slider: Slider = %VolumeSlider
@onready var restart_btn: Button = %RestartBtn

# var notifications = [] # todo: use queue for multiple

func _ready():
    SignalBus.angle_updated.connect(on_angle_updated)
    SignalBus.notify_ui.connect(on_notify_ui)
    SignalBus.throttle_updated.connect(on_throttle_updated)
    SignalBus.score_updated.connect(set_score_label_text)
    SignalBus.distance_updated.connect(set_distance_label_text)
    
    volume_slider.value_changed.connect(on_volume_changed)

    # Defaults
    notify_label.text = ""
    throttle_progress.value = 0
    restart_btn.visible = false

    set_score_label_text(0)
    set_distance_label_text(0)
    set_max_score_label_text(0)
    set_max_distance_label_text(0)
    set_max_clean_runs_label_text(0)
    volume_slider.value = 0.75 # TODO: load from save

func switch_panels(state: MainGame.GameState):
    match state:
        MainGame.GameState.MAIN_MENU:
            game_panel.visible = false
            pause_menu_panel.visible = false
            main_menu_panel.visible = true
        MainGame.GameState.PLAYING, MainGame.GameState.RUN_OVER:
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

    # Set color from val
    var color: Color
    if pct <= 66:
        # From white (0) to yellow (66)
        var t = pct / 66.0
        color = Color.hex(0x12b100ff).lerp(Color.YELLOW, t)
    else:
        # From yellow (66) to red (90)
        var t = (pct - 66.0) / 66.0
        color = Color.YELLOW.lerp(Color.RED, t)

    var new_stylebox: StyleBoxFlat = throttle_progress.get_theme_stylebox("fill").duplicate()
    new_stylebox.bg_color = color
    throttle_progress.add_theme_stylebox_override('fill', new_stylebox)

func on_angle_updated(angle_deg: float):
    angle_label.text = "%.0f°" % abs(angle_deg)

    # Set color from val
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

func on_notify_ui(msg: String, duration: float = notify_time_sec):
    notify_label.text = msg
    await get_tree().create_timer(duration).timeout
    notify_label.text = ""
    notify_finished.emit()
#endregion

func on_volume_changed(value: float):
    SignalBus.volume = value

##region label setters
func set_score_label_text(score: int):
    score_label.text = "Score: %d" % score

func set_distance_label_text(distance: float):
    distance_label.text = "Distance: %.0fm" % distance

func set_max_score_label_text(score: int):
    max_score_label.text = "High Score: %d" % score

func set_max_distance_label_text(distance: float):
    max_distance_label.text = "Max Distance: %.0fm" % distance

func set_max_clean_runs_label_text(clean_runs: int):
    max_clean_runs_label.text = "Clean Runs: %d" % clean_runs
#
