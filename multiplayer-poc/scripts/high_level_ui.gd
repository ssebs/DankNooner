extends Control

@onready var server_btn: Button = %Server
@onready var client_btn: Button = %Client
@onready var host_btn: Button = %Host

func _ready():
    server_btn.pressed.connect(_on_server_pressed)
    client_btn.pressed.connect(_on_client_pressed)
    host_btn.pressed.connect(_on_host_pressed)


func _on_server_pressed():
    HighLevelNetworkHandler.start_server()

func _on_client_pressed():
    HighLevelNetworkHandler.start_client()

func _on_host_pressed():
    HighLevelNetworkHandler.start_host()
