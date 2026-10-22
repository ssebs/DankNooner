@tool
class_name CreditsMenuState extends MenuState

const CREDITS_FILES: Array[String] = [
	"res://resources/credits/people.md",
	"res://resources/credits/assets.md",
	"res://resources/credits/music.md",
]
const LINK_COLOR := "#41afff"

@onready var credits_text: RichTextLabel = %CreditsText
@onready var close_credits_btn: Button = %CloseCreditsBtn


func _ready():
	super._ready()
	if Engine.is_editor_hint():
		return
	var bbcode := ""
	for path in CREDITS_FILES:
		bbcode += _md_to_bbcode(FileAccess.open(path, FileAccess.READ).get_as_text())
	credits_text.text = bbcode


func Enter(state_context: StateContext):
	return_state = state_context.return_state
	ui.show()
	close_credits_btn.pressed.connect(_on_close_credits_pressed)
	credits_text.meta_clicked.connect(_on_link_clicked)


func Exit(_state_context: StateContext):
	ui.hide()
	close_credits_btn.pressed.disconnect(_on_close_credits_pressed)
	credits_text.meta_clicked.disconnect(_on_link_clicked)


## Only the subset the credits use: "#"/"##" headings, nested "- " bullets, [text](url) links.
## "> " lines are author notes and skipped. Any other "[" would be parsed as BBCode.
func _md_to_bbcode(md: String) -> String:
	var link_re := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	var out := ""
	var depth := 0
	for raw_line in md.split("\n"):
		var line := raw_line.strip_edges(false, true)
		var text := line.lstrip(" ")
		var line_depth := 0
		if text.begins_with("- "):
			line_depth = int((line.length() - text.length()) / 2.0) + 1
			text = text.substr(2)
		while depth < line_depth:
			out += "[ul]\n"
			depth += 1
		while depth > line_depth:
			out += "[/ul]\n"
			depth -= 1

		if text.begins_with("> "):
			continue
		if text.begins_with("## "):
			text = "[b][font_size=32]%s[/font_size][/b]" % text.substr(3)
		elif text.begins_with("# "):
			text = "[b][font_size=48]%s[/font_size][/b]" % text.substr(2)
		out += link_re.sub(text, "[url=$2][color=%s]$1[/color][/url]" % LINK_COLOR, true) + "\n"

	while depth > 0:
		out += "[/ul]\n"
		depth -= 1
	return out


func _on_link_clicked(meta: Variant):
	OS.shell_open(str(meta))


func _on_close_credits_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_close_credits_pressed()
