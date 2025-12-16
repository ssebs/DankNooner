extends Control

@onready var text_chat_container: VBoxContainer = %TextChatContainer
@onready var text_entry: LineEdit = %Entry

func _ready():
    text_entry.text_submitted.connect(on_submit)

# TODO: press enter to open chat, esc to close it, enter to send msg,
#   pause input in other parts of game

func on_submit(text: String):
    add_label_to_screen.rpc(text, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func add_label_to_screen(text: String, id: int):
    var new_label = Label.new()
    new_label.text = "@" + str(id) + " | " + text
    text_chat_container.add_child(new_label)
    text_entry.text = ""
