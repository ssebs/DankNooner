class_name LobbyStateContext extends StateContext

enum Mode { FREEROAM, STORY, HOST, JOIN }

var mode: Mode
var ip_addr: String
## STORY: definition name of the tutorial event to start; "" = the level's auto_start_event.
var event_name: String


static func NewHost(rs: MenuState, ip: String) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.HOST
	ctx.ip_addr = ip
	ctx.return_state = rs
	return ctx


static func NewJoin(rs: MenuState, ip: String) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.JOIN
	ctx.ip_addr = ip
	ctx.return_state = rs
	return ctx


static func NewFreeRoam(
	rs: MenuState,
) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.FREEROAM
	ctx.return_state = rs
	return ctx


static func NewStory(
	rs: MenuState,
	story_event_name: String = "",
) -> LobbyStateContext:
	var ctx = LobbyStateContext.new()
	ctx.mode = Mode.STORY
	ctx.event_name = story_event_name
	ctx.return_state = rs
	return ctx
