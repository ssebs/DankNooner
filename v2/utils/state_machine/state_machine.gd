@tool
## State Machine manages transitions between States.
## Auto-registers all child States
## Child states can transition by emitting transitioned()
class_name StateMachine extends Node

## After Enter() of new transition
signal state_transitioned(new_state: State)

## _transition_to is deferred on _ready
@export var initial_state: State
@export var is_debug: bool = false

## When a new State is registered, add it to the dictionary
var states: Dictionary[String, State] = {}
var current_state: State


func _ready():
	load_child_states()
	if initial_state:
		# _transition_to(initial_state)
		call_deferred("_transition_to", initial_state)


#region Public API
## Register states from this node's children
func load_child_states():
	for child in get_children():
		if child is State:
			if is_debug:
				print("Found %s, registering to this state machine" % child)
			register_state(child)


## Add state to Dict & connect the transitioned signal
func register_state(new_state: State):
	var ok = states.set(new_state.name, new_state)
	if !ok:
		printerr("Failed to register state %s" % new_state)
		return

	new_state.state_machine_ref = self
	new_state.transitioned.connect(_transition_to)


## Remove state from Dict & disconnect transitioned signal
func deregister_state(state: State):
	state.transitioned.disconnect(_transition_to)
	states.erase(state.name)


## Transition to new_state, not to be called from children!
func request_state_change(new_state: State):
	_transition_to(new_state)


## Get a State in this State Machine by the State's name
func get_state_by_name(state_name: String) -> State:
	var st = states.get(state_name)
	if st == null:
		printerr("Could not get state %s" % state_name)
	return st


#endregion


## Updates current_state to new_state, runs Exit() on old and Enter() on new
func _transition_to(new_state: State):
	if is_debug:
		print("transition_to: %s" % new_state)

	var ok = states.has(new_state.name)
	if !ok:
		printerr("Could not find %s in state machine" % new_state)
		return

	if new_state == current_state:
		if is_debug:
			print("transition_to: %s states match, not transitioning" % current_state)
		return

	if current_state:
		if is_debug:
			print("Leaving: ", current_state)
		current_state.Exit()

	current_state = new_state
	if is_debug:
		print("Entering: ", current_state.name)
	new_state.Enter()

	state_transitioned.emit(new_state)


## Runs current_state.Update()
func _process(delta):
	if current_state:
		current_state.Update(delta)


## Runs current_state.Physics_Update()
func _physics_process(delta):
	if current_state:
		current_state.Physics_Update(delta)
