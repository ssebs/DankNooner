@tool
class_name AudioManager extends BaseManager

## Looping engine sounds driven by RPM. Used by BikeSkinDefinition.engine_sound_id
## to pick which sound `play_revs()` activates.
enum EngineSfx {
	NINJA500,
	GROM,
	XSR900,
}

## Generic SFX id for callers (e.g. GameModeTasks) that need to play a sound
## without holding a typed ref to a specific SoundEvent. Add new entries at the end (scenes save
## them as ints) and to `_sfx_events` in _ready.
enum Sfx {
	STARTUP,
	BOWLING_CRASH,
	COUNTDOWN_3SEC,
	COUNTDOWN_5SEC,
	COUNTDOWN_LOOP,
	MENU_CLICK,
	MENU_ERR,
	MAXIMIZE,
	MINIMIZE,
	MOUSE_CLICK,
	CLUNK_GEAR_CHANGE,
	BONE_CRACK,
	DING,
	FAHH,
	TBELL,
	VINE_BOOM,
	TADA,
	NUKE,
	COD_ZOMBIES_KABOOM,
	TIRE_SQUEAL,
	BONK,
	GLUG_GLUG,
	WATER_FLOWING,
	NOS_BOOST,
	AIRHORN,
	ANIME_WOW,
	ANOTHER_ONE,
	AUUGHHH,
	BICYCLE_HORN,
	BOAT_HORN,
	CAR_HORN,
	CARTOON_RUNNING,
	CLOWN_HORN,
	CONFETTI_HORN,
	DISCORD_CALL,
	DISCORD_NOTIFICATION,
	ELEVATOR_MUSIC,
	FLASHBANG,
	FOG_HORN,
	HAVE_TO_SAY_YOURE_FINE,
	HEAVENLY_MUSIC,
	HOMER_BARTS_OUT,
	HUH,
	INCEPTION_HORN,
	ITALIAN_BRAINROT,
	LIZARD,
	MEOW,
	NELLY_AHH,
	QUACK,
	RIZZ,
	SAD_MEOW_SONG,
	SAD_LOSS_HORN,
	SAD_VIOLIN,
	SPONGE_STANK,
	SQUIDWARD_WALKING,
	VINTAGE_HORN,
	YOU_GOT_MAIL,
	FOUR_BIG_GUYS,
	DU_BIST_GUT_GENUG,
	HAH_CHEW,
	METAL_PIPE,
	WHAT_THE_DOG_DOIN,
}

@export var settings_manager: SettingsManager
@export_tool_button("Play Startup") var tool_btn_1 = play_startup

## Map of settings_manager key → audio bus name. Buses are defined in `default_bus_layout.tres`
## (must be created in the editor — runtime AudioServer.add_bus() doesn't work on web exports).
const VOLUME_SETTING_MAP: Dictionary = {
	"master_vol": "Master",
	"menu_vol": "Menu",
	"sfx_vol": "SFX",
	"music_vol": "Music",
}

# TODO - use InputState to switch which buses are routed where

var sounds_container: Node
var startup: SoundEvent
var ninja500_revs: EngineSoundEvent
var grom_revs: EngineSoundEvent
var xsr900_revs: EngineSoundEvent
var bowling_crash: SoundEvent
var countdown_3sec: SoundEvent
var countdown_5sec: SoundEvent
var countdown_loop: SoundEvent
var menu_click: SoundEvent
var menu_err: SoundEvent
var maximize: SoundEvent
var minimize: SoundEvent
var mouse_click: SoundEvent
var clunk_gear_change: SoundEvent
var bone_crack: SoundEvent
var ding: SoundEvent
var fahh: SoundEvent
var tbell: SoundEvent
var vine_boom: SoundEvent
var tada: SoundEvent
var nuke: SoundEvent
var cod_zombies_kaboom: SoundEvent
var tire_squeal: SoundEvent
var bonk: SoundEvent
var glug_glug: SoundEvent
var water_flowing: SoundEvent
var exhaust_burble: SoundEvent
var nos_boost: SoundEvent
var airhorn: SoundEvent
var anime_wow: SoundEvent
var another_one: SoundEvent
var auughhh: SoundEvent
var bicycle_horn: SoundEvent
var boat_horn: SoundEvent
var car_horn: SoundEvent
var cartoon_running: SoundEvent
var clown_horn: SoundEvent
var confetti_horn: SoundEvent
var discord_call: SoundEvent
var discord_notification: SoundEvent
var elevator_music: SoundEvent
var flashbang: SoundEvent
var fog_horn: SoundEvent
var have_to_say_youre_fine: SoundEvent
var heavenly_music: SoundEvent
var homer_barts_out: SoundEvent
var huh: SoundEvent
var inception_horn: SoundEvent
var italian_brainrot: SoundEvent
var lizard: SoundEvent
var meow: SoundEvent
var nelly_ahh: SoundEvent
var quack: SoundEvent
var rizz: SoundEvent
var sad_meow_song: SoundEvent
var sad_loss_horn: SoundEvent
var sad_violin: SoundEvent
var sponge_stank: SoundEvent
var squidward_walking: SoundEvent
var vintage_horn: SoundEvent
var you_got_mail: SoundEvent
var four_big_guys: SoundEvent
var du_bist_gut_genug: SoundEvent
var hah_chew: SoundEvent
var metal_pipe: SoundEvent
var what_the_dog_doin: SoundEvent

## Map of Sfx → SoundEvent node, populated in _ready.
var _sfx_events: Dictionary = {}
## Map of EngineSfx → EngineSoundEvent node, populated in _ready.
var _engine_sounds: Dictionary = {}
## Currently-playing engine sound id, or -1 if none.
var _active_engine_sfx: int = -1
## Round-robin pool of decel pop players (children of %ExhaustPops) + the next index to play.
var _exhaust_pops: Array[SoundEvent] = []
var _exhaust_pop_idx: int = 0
var _audio_disabled := false
var _app_focused := true


func _ready():
	sounds_container = get_node_or_null("%Sounds")
	startup = get_node_or_null("%Startup") as SoundEvent
	ninja500_revs = get_node_or_null("%Ninja500Revs") as EngineSoundEvent
	grom_revs = get_node_or_null("%GromRevs") as EngineSoundEvent
	xsr900_revs = get_node_or_null("%Xsr900Revs") as EngineSoundEvent
	bowling_crash = get_node_or_null("%BowlingCrash") as SoundEvent
	countdown_3sec = get_node_or_null("%Countdown3Sec") as SoundEvent
	countdown_5sec = get_node_or_null("%Countdown5Sec") as SoundEvent
	countdown_loop = get_node_or_null("%CountdownLoop") as SoundEvent
	menu_click = get_node_or_null("%MenuClick") as SoundEvent
	menu_err = get_node_or_null("%MenuErr") as SoundEvent
	maximize = get_node_or_null("%Maximize") as SoundEvent
	minimize = get_node_or_null("%Minimize") as SoundEvent
	mouse_click = get_node_or_null("%MouseClick") as SoundEvent
	clunk_gear_change = get_node_or_null("%ClunkGearChange") as SoundEvent
	bone_crack = get_node_or_null("%BoneCrack") as SoundEvent
	ding = get_node_or_null("%Ding") as SoundEvent
	fahh = get_node_or_null("%Fahh") as SoundEvent
	tbell = get_node_or_null("%TBell") as SoundEvent
	vine_boom = get_node_or_null("%VineBoom") as SoundEvent
	tada = get_node_or_null("%Tada") as SoundEvent
	nuke = get_node_or_null("%Nuke") as SoundEvent
	cod_zombies_kaboom = get_node_or_null("%CODZombiesKaboom") as SoundEvent
	tire_squeal = get_node_or_null("%TireSqueal") as SoundEvent
	bonk = get_node_or_null("%Bonk") as SoundEvent
	glug_glug = get_node_or_null("%GlugGlug") as SoundEvent
	water_flowing = get_node_or_null("%WaterFlowing") as SoundEvent
	exhaust_burble = get_node_or_null("%ExhaustBurble") as SoundEvent
	nos_boost = get_node_or_null("%NOSBoost") as SoundEvent
	airhorn = get_node_or_null("%Airhorn") as SoundEvent
	anime_wow = get_node_or_null("%AnimeWow") as SoundEvent
	another_one = get_node_or_null("%AnotherOne") as SoundEvent
	auughhh = get_node_or_null("%Auughhh") as SoundEvent
	bicycle_horn = get_node_or_null("%BicycleHorn") as SoundEvent
	boat_horn = get_node_or_null("%BoatHorn") as SoundEvent
	car_horn = get_node_or_null("%CarHorn") as SoundEvent
	cartoon_running = get_node_or_null("%CartoonRunning") as SoundEvent
	clown_horn = get_node_or_null("%ClownHorn") as SoundEvent
	confetti_horn = get_node_or_null("%ConfettiHorn") as SoundEvent
	discord_call = get_node_or_null("%DiscordCall") as SoundEvent
	discord_notification = get_node_or_null("%DiscordNotification") as SoundEvent
	elevator_music = get_node_or_null("%ElevatorMusic") as SoundEvent
	flashbang = get_node_or_null("%Flashbang") as SoundEvent
	fog_horn = get_node_or_null("%FogHorn") as SoundEvent
	have_to_say_youre_fine = get_node_or_null("%HaveToSayYoureFine") as SoundEvent
	heavenly_music = get_node_or_null("%HeavenlyMusic") as SoundEvent
	homer_barts_out = get_node_or_null("%HomerBartsOut") as SoundEvent
	huh = get_node_or_null("%Huh") as SoundEvent
	inception_horn = get_node_or_null("%InceptionHorn") as SoundEvent
	italian_brainrot = get_node_or_null("%ItalianBrainrot") as SoundEvent
	lizard = get_node_or_null("%Lizard") as SoundEvent
	meow = get_node_or_null("%Meow") as SoundEvent
	nelly_ahh = get_node_or_null("%NellyAhh") as SoundEvent
	quack = get_node_or_null("%Quack") as SoundEvent
	rizz = get_node_or_null("%Rizz") as SoundEvent
	sad_meow_song = get_node_or_null("%SadMeowSong") as SoundEvent
	sad_loss_horn = get_node_or_null("%SadLossHorn") as SoundEvent
	sad_violin = get_node_or_null("%SadViolin") as SoundEvent
	sponge_stank = get_node_or_null("%SpongeStank") as SoundEvent
	squidward_walking = get_node_or_null("%SquidwardWalking") as SoundEvent
	vintage_horn = get_node_or_null("%VintageHorn") as SoundEvent
	you_got_mail = get_node_or_null("%YouGotMail") as SoundEvent
	four_big_guys = get_node_or_null("%FourBigGuys") as SoundEvent
	du_bist_gut_genug = get_node_or_null("%DuBistGutGenug") as SoundEvent
	hah_chew = get_node_or_null("%HahChew") as SoundEvent
	metal_pipe = get_node_or_null("%MetalPipe") as SoundEvent
	what_the_dog_doin = get_node_or_null("%WhatTheDogDoin") as SoundEvent
	for pop in get_node("%ExhaustPops").get_children():
		if pop is SoundEvent:
			_exhaust_pops.append(pop)

	_sfx_events = {
		Sfx.STARTUP: startup,
		Sfx.BOWLING_CRASH: bowling_crash,
		Sfx.COUNTDOWN_3SEC: countdown_3sec,
		Sfx.COUNTDOWN_5SEC: countdown_5sec,
		Sfx.COUNTDOWN_LOOP: countdown_loop,
		Sfx.MENU_CLICK: menu_click,
		Sfx.MENU_ERR: menu_err,
		Sfx.MAXIMIZE: maximize,
		Sfx.MINIMIZE: minimize,
		Sfx.MOUSE_CLICK: mouse_click,
		Sfx.CLUNK_GEAR_CHANGE: clunk_gear_change,
		Sfx.BONE_CRACK: bone_crack,
		Sfx.DING: ding,
		Sfx.FAHH: fahh,
		Sfx.TBELL: tbell,
		Sfx.VINE_BOOM: vine_boom,
		Sfx.TADA: tada,
		Sfx.NUKE: nuke,
		Sfx.COD_ZOMBIES_KABOOM: cod_zombies_kaboom,
		Sfx.TIRE_SQUEAL: tire_squeal,
		Sfx.BONK: bonk,
		Sfx.GLUG_GLUG: glug_glug,
		Sfx.WATER_FLOWING: water_flowing,
		Sfx.NOS_BOOST: nos_boost,
		Sfx.AIRHORN: airhorn,
		Sfx.ANIME_WOW: anime_wow,
		Sfx.ANOTHER_ONE: another_one,
		Sfx.AUUGHHH: auughhh,
		Sfx.BICYCLE_HORN: bicycle_horn,
		Sfx.BOAT_HORN: boat_horn,
		Sfx.CAR_HORN: car_horn,
		Sfx.CARTOON_RUNNING: cartoon_running,
		Sfx.CLOWN_HORN: clown_horn,
		Sfx.CONFETTI_HORN: confetti_horn,
		Sfx.DISCORD_CALL: discord_call,
		Sfx.DISCORD_NOTIFICATION: discord_notification,
		Sfx.ELEVATOR_MUSIC: elevator_music,
		Sfx.FLASHBANG: flashbang,
		Sfx.FOG_HORN: fog_horn,
		Sfx.HAVE_TO_SAY_YOURE_FINE: have_to_say_youre_fine,
		Sfx.HEAVENLY_MUSIC: heavenly_music,
		Sfx.HOMER_BARTS_OUT: homer_barts_out,
		Sfx.HUH: huh,
		Sfx.INCEPTION_HORN: inception_horn,
		Sfx.ITALIAN_BRAINROT: italian_brainrot,
		Sfx.LIZARD: lizard,
		Sfx.MEOW: meow,
		Sfx.NELLY_AHH: nelly_ahh,
		Sfx.QUACK: quack,
		Sfx.RIZZ: rizz,
		Sfx.SAD_MEOW_SONG: sad_meow_song,
		Sfx.SAD_LOSS_HORN: sad_loss_horn,
		Sfx.SAD_VIOLIN: sad_violin,
		Sfx.SPONGE_STANK: sponge_stank,
		Sfx.SQUIDWARD_WALKING: squidward_walking,
		Sfx.VINTAGE_HORN: vintage_horn,
		Sfx.YOU_GOT_MAIL: you_got_mail,
		Sfx.FOUR_BIG_GUYS: four_big_guys,
		Sfx.DU_BIST_GUT_GENUG: du_bist_gut_genug,
		Sfx.HAH_CHEW: hah_chew,
		Sfx.METAL_PIPE: metal_pipe,
		Sfx.WHAT_THE_DOG_DOIN: what_the_dog_doin,
	}
	_engine_sounds = {
		EngineSfx.NINJA500: ninja500_revs,
		EngineSfx.GROM: grom_revs,
		EngineSfx.XSR900: xsr900_revs,
	}

	if Engine.is_editor_hint():
		return

	settings_manager.all_settings_changed.connect(_on_all_settings_changed)
	settings_manager.setting_updated.connect(_on_setting_updated)

	_audio_disabled = "--disable-audio" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), _audio_disabled)


func _notification(what: int):
	if what != NOTIFICATION_APPLICATION_FOCUS_IN and what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	_app_focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
	# Focus events fire in the editor and before settings load; next settings load applies it
	if Engine.is_editor_hint() or settings_manager.current_settings.is_empty():
		return
	_apply_master_mute()


func _on_all_settings_changed(new_settings: Dictionary):
	_apply_master_mute()
	for setting_key in VOLUME_SETTING_MAP.keys():
		var bus_name: String = VOLUME_SETTING_MAP[setting_key]
		var setting_value: float = new_settings[setting_key]
		_apply_bus_volume(bus_name, setting_value)


func _on_setting_updated(setting_key: String, setting_value: Variant):
	if !VOLUME_SETTING_MAP.has(setting_key):
		return
	_apply_bus_volume(VOLUME_SETTING_MAP[setting_key], setting_value)


func _apply_bus_volume(bus_name: String, linear_volume: float):
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		DebugUtils.DebugErrMsg("audio bus not found: %s" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear_volume))


func _apply_master_mute():
	var s := settings_manager.current_settings
	var muted: bool = _audio_disabled or s["mute"] or (s["mute_unfocused"] and !_app_focused)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), muted)


## Silences gameplay SFX (engine revs etc.) without touching the user's volume setting.
func set_sfx_muted(muted: bool):
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX"), muted)


## Plays the engine sound configured by `bike_def`. Stops any previously-active
## engine sound first so two loops don't overlap when a player swaps bikes.
func play_revs(bike_def: BikeSkinDefinition):
	var sfx_id: int = bike_def.engine_sound_id
	if _active_engine_sfx != -1 and _active_engine_sfx != sfx_id:
		_engine_sounds[_active_engine_sfx].stop()
	var sound: EngineSoundEvent = _engine_sounds[sfx_id]
	sound.min_pitch = bike_def.engine_min_pitch
	sound.max_pitch = bike_def.engine_max_pitch
	sound.rpm_curve = bike_def.engine_rpm_pitch_curve
	sound.blend_curve = bike_def.engine_blend_curve
	sound.play_engine()
	_active_engine_sfx = sfx_id


func stop_revs():
	if _active_engine_sfx == -1:
		return
	_engine_sounds[_active_engine_sfx].stop_engine()
	_active_engine_sfx = -1


func update_revs_rpm(bike_def: BikeSkinDefinition, val: float):
	_engine_sounds[bike_def.engine_sound_id].set_parameter("RPM", val)


## The authored engine `bike_def` uses, for positional copies (EngineSoundEvent3D).
func get_engine_sound(bike_def: BikeSkinDefinition) -> EngineSoundEvent:
	return _engine_sounds[bike_def.engine_sound_id]


## The next decel pop, round-robin. Add variants by dropping AudioStreamPlayers under the
## ExhaustPops node — they join the rotation automatically, each played at its authored level.
func next_exhaust_pop() -> SoundEvent:
	var pop := _exhaust_pops[_exhaust_pop_idx]
	_exhaust_pop_idx = (_exhaust_pop_idx + 1) % _exhaust_pops.size()
	return pop


func play_nos_boost():
	nos_boost.play()


func play_startup():
	startup.play()


func play_bowling_crash():
	bowling_crash.play()


func play_countdown_3sec():
	countdown_3sec.play()


func play_countdown_5sec():
	countdown_5sec.play()


func play_countdown_loop():
	countdown_loop.play()


func play_menu_click():
	menu_click.play()


func play_menu_err():
	menu_err.play()


func play_maximize():
	maximize.play()


func play_minimize():
	minimize.play()


func play_mouse_click():
	mouse_click.play()


func play_clunk_gear_change():
	clunk_gear_change.play()


func play_bone_crack():
	bone_crack.play()


func play_ding():
	ding.play()


func play_fahh():
	fahh.play()


func play_tbell():
	tbell.play()


func play_vine_boom():
	vine_boom.play()


func play_tada():
	tada.play()


func play_nuke():
	nuke.play()


func play_cod_zombies_kaboom():
	cod_zombies_kaboom.play()


func play_bonk():
	bonk.play()


func play_sfx(id: Sfx):
	get_sound_event(id).play()


func stop_sfx(id: Sfx):
	get_sound_event(id).stop()


func get_sound_event(id: Sfx) -> SoundEvent:
	return _sfx_events[id]


func stop_all():
	for sound in sounds_container.get_children():
		if sound is EngineSoundEvent:
			sound.stop_engine()
		elif sound is SoundEvent:
			sound.stop()
