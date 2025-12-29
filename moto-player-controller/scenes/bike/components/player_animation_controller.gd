class_name PlayerAnimationController extends Node

@onready var character_skel: Skeleton3D = null

# Shared state
var state: BikeState

# Input state (from signals)
var lean_angle: float = 0.0

func setup(bike_state: BikeState, input: BikeInput, skel: Skeleton3D):
    state = bike_state
    character_skel = skel

