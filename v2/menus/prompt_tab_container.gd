@tool
## TabContainer with the LB/RB tab-switch prompts flanking its tab strip, like the garage's.
## Pad only: the mouse clicks the tabs. The owning menu calls show_prompts() on device change.
class_name PromptTabContainer extends TabContainer

const INPUT_PROMPT_SCENE := preload("res://player/hud_elements/input_prompt.tscn")

var _prev_prompt: InputPrompt
var _next_prompt: InputPrompt


func _ready():
	if Engine.is_editor_hint():
		return
	_prev_prompt = _add_prompt("ui_tab_prev")
	_next_prompt = _add_prompt("ui_tab_next")
	get_tab_bar().resized.connect(_place_prompts)
	show_prompts(false)


func show_prompts(gamepad: bool):
	for prompt: InputPrompt in [_prev_prompt, _next_prompt]:
		# refresh() hides it when the action is unbound.
		prompt.refresh(true)
		prompt.visible = prompt.visible and gamepad
	# Shift the tabs right to make room for the left prompt.
	var margin := _prev_prompt.get_combined_minimum_size().x if _prev_prompt.visible else 0.0
	add_theme_constant_override("side_margin", int(margin))
	_place_prompts()


## Parented to the TabBar: any Control child of a TabContainer, even an internal one, becomes a tab.
func _add_prompt(action: String) -> InputPrompt:
	var prompt: InputPrompt = INPUT_PROMPT_SCENE.instantiate()
	prompt.action = action
	get_tab_bar().add_child(prompt)
	return prompt


## In TabBar space: prev sits in the side_margin left of the bar, next at its right end.
func _place_prompts():
	var bar := get_tab_bar()
	for prompt: InputPrompt in [_prev_prompt, _next_prompt]:
		prompt.size = prompt.get_combined_minimum_size()
		prompt.position.y = (bar.size.y - prompt.size.y) / 2
	_prev_prompt.position.x = -_prev_prompt.size.x
	_next_prompt.position.x = bar.size.x - _next_prompt.size.x
