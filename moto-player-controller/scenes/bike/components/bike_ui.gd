class_name BikeUI extends Node

@onready var gear_label: Label = null
@onready var speed_label: Label = null
@onready var throttle_bar: ProgressBar = null
@onready var brake_danger_bar: ProgressBar = null
@onready var clutch_bar: ProgressBar = null
@onready var difficulty_label: Label = null

# Shared state
var state: BikeState

# Input state (from signals)
var throttle: float = 0.0
var front_brake: float = 0.0

# Component references for vibration
var bike_input: BikeInput
var bike_crash: BikeCrash
var bike_tricks: BikeTricks


func setup(bike_state: BikeState, input: BikeInput, crash: BikeCrash, tricks: BikeTricks,
        gear: Label, spd: Label, throttle_b: ProgressBar, brake: ProgressBar, clutch: ProgressBar, difficulty: Label
    ):
    state = bike_state
    bike_input = input
    bike_crash = crash
    bike_tricks = tricks

    gear_label = gear
    speed_label = spd
    throttle_bar = throttle_b
    brake_danger_bar = brake
    clutch_bar = clutch
    difficulty_label = difficulty

    input.throttle_changed.connect(func(v): throttle = v)
    input.front_brake_changed.connect(func(v): front_brake = v)
    input.difficulty_toggled.connect(_on_difficulty_toggled)


func update_ui(rpm_ratio: float):
    _update_labels()
    _update_bars(rpm_ratio)
    _update_vibration()
    _update_difficulty_display()


func _update_labels():
    if !gear_label or !speed_label:
        return

    if state.is_stalled:
        gear_label.text = "STALLED\nGear: %d" % state.current_gear
    else:
        gear_label.text = "Gear: %d" % state.current_gear

    speed_label.text = "Speed: %d" % int(state.speed)


func _update_bars(rpm_ratio: float):
    if !throttle_bar or !brake_danger_bar:
        return

    throttle_bar.value = throttle

    if rpm_ratio > 0.9:
        throttle_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
    else:
        throttle_bar.modulate = Color(0.2, 0.8, 0.2) # Green

    brake_danger_bar.value = front_brake

    if state.brake_danger_level > 0.1:
        var danger_color = Color(1.0, 1.0 - state.brake_danger_level, 0.0)
        brake_danger_bar.modulate = danger_color
    else:
        brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)

    if clutch_bar:
        clutch_bar.value = state.clutch_value
        clutch_bar.modulate = Color(0.8, 0.6, 0.2) # Orange/yellow


# TODO: move this
func _update_vibration():
    if !bike_input:
        return

    var weak_total = 0.0
    var strong_total = 0.0

    # Get vibration from components
    if bike_crash:
        var brake_vibe = bike_crash.get_brake_vibration()
        weak_total += brake_vibe.x
        strong_total += brake_vibe.y

    if bike_tricks:
        var fishtail_vibe = bike_tricks.get_fishtail_vibration()
        weak_total += fishtail_vibe.x
        strong_total += fishtail_vibe.y

    # Apply vibration through input component
    bike_input.add_vibration(weak_total, strong_total)


# TODO: refactor, this is the only thing that uses signals from bike_input
func _on_difficulty_toggled():
    state.is_easy_mode = !state.is_easy_mode
    _update_difficulty_display()


func _update_difficulty_display():
    if !difficulty_label:
        return
    if state.is_easy_mode:
        difficulty_label.text = "Easy"
        difficulty_label.modulate = Color(0.2, 0.8, 0.2)
    else:
        difficulty_label.text = "Hard"
        difficulty_label.modulate = Color(1.0, 0.3, 0.3)
