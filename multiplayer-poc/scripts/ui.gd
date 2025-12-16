extends Control

@onready var server_btn: Button = %Server
@onready var client_btn: Button = %Client
@onready var ip_entry: LineEdit = %IPEntry

func _ready():
    server_btn.pressed.connect(_on_server_pressed)
    client_btn.pressed.connect(_on_client_pressed)

func _on_server_pressed():
    self.hide()
    MultiplayerManager.start_server()

func _on_client_pressed():
    self.hide()
    MultiplayerManager.start_client(ip_entry.text)
