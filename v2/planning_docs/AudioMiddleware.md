# Audio Middleware

Lightweight replacement for FMOD using Godot's built-in `AudioStreamPlayer` + audio buses. Web-export friendly.

## Why

FMOD doesn't work in web exports. We needed something that:

- Plays one-shot sounds (startup jingle)
- Plays looping sounds with a runtime-tunable parameter (engine RPM → pitch)
- Routes through Master / Menu / SFX / Music buses, controlled by `SettingsManager` sliders
- Works on web

The middleware is intentionally thin — a class wrapping `AudioStreamPlayer` plus a virtual `set_parameter()` hook, mimicking FMOD's event/parameter API but with ~50 lines of code.

## Files

| File                                                | Role                                                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `utils/custom_audio_middleware/sound_event.gd`      | `class_name SoundEvent extends AudioStreamPlayer`. Adds `loop` flag and virtual `set_parameter()` |
| `utils/custom_audio_middleware/engine_sound_event.gd` | `class_name EngineSoundEvent extends SoundEvent`. Maps `RPM` (0..1) → pitch via a `Curve`         |
| `default_bus_layout.tres` (project root)            | Defines `Master`, `Menu`, `SFX`, `Music` buses. Auto-loaded by Godot                              |
| `managers/audio_manager.gd` / `.tscn`               | Hosts the sound events, applies setting → bus volumes                                             |

## SoundEvent (base class)

A scripted `AudioStreamPlayer`. Use it directly for fire-and-forget sounds, or subclass to add parameter behavior.

Exported properties:

- `stream: AudioStream` — inherited from `AudioStreamPlayer`
- `bus: StringName` — inherited; pick `Menu`, `SFX`, `Music`, or `Master`
- `volume_db: float` — inherited
- `loop: bool` — duplicates the stream at runtime and sets `stream.loop = true` so the shared resource is never mutated globally. Use this for engine loops, music, etc. The OGG/MP3 stream's import setting can also enable looping — `loop` is just a runtime override

Virtual hook:

```gdscript
func set_parameter(_param_name: String, _value: float) -> void:
    pass
```

Override in subclasses to react to gameplay values (RPM, speed, distance, etc.).

## EngineSoundEvent (subclass example)

Maps `RPM` in `[0..1]` through a `Curve` to semitones, then to `pitch_scale = 2^(st/12)`. The default curve matches the old FMOD project: `(0, 0)`, `(0.2, 2)`, `(1.0, 18)`.

```gdscript
func set_parameter(param_name: String, value: float) -> void:
    if param_name != "RPM":
        return
    var semitones: float = rpm_to_semitones.sample(clampf(value, 0.0, 1.0))
    pitch_scale = pow(2.0, semitones / 12.0)
```

Tune the curve in the inspector — no code change needed.

## AudioManager wiring

`managers/audio_manager.tscn` holds the sound events as children of `Sounds`:

```
AudioManager (Node, script: audio_manager.gd)
└── Sounds (Node, %Sounds)
    ├── Startup       (AudioStreamPlayer, script: sound_event.gd,        %Startup,       bus: Menu)
    └── Ninja500Revs  (AudioStreamPlayer, script: engine_sound_event.gd, %Ninja500Revs,  bus: SFX, loop = true)
```

`AudioManager` then exposes the same public API the rest of the codebase used to call into FMOD:

| Method                          | What it does                              |
| ------------------------------- | ----------------------------------------- |
| `play_startup()`                | `startup.play()`                          |
| `play_ninja500_revs()`          | `ninja500_revs.play()`                    |
| `update_ninja500_rpm(val)`      | `ninja500_revs.set_parameter("RPM", val)` |
| `stop_all()`                    | Stops every `SoundEvent` under `%Sounds`  |

Volume control listens to `SettingsManager`:

- `VOLUME_SETTING_MAP` maps each setting key (`master_vol`, `menu_vol`, `sfx_vol`, `music_vol`) to a bus name
- On `setting_updated` / `all_settings_changed`, it calls `AudioServer.set_bus_volume_db(idx, linear_to_db(value))`
- `--disable-audio` CLI arg mutes the Master bus

## Audio buses

Defined in `default_bus_layout.tres` at the project root. Godot loads this automatically on startup.

**Important:** `AudioServer.add_bus()` at runtime does **not** work in web exports. Buses must exist in the layout file. To add a new bus, edit the layout file directly or use Godot's Audio panel and save the layout.

Current layout:

```
Master     →  (output)
Menu       →  Master
SFX        →  Master
MusicDuck  →  Master
Music      →  MusicDuck
```

`MusicDuck` has no setting; it exists so ducking never touches the user's `Music` volume (see [Music](#music)).

## Web export considerations

Two web-specific behaviors are already handled:

1. **Buses defined in editor, not code** — `default_bus_layout.tres` ships with the project; runtime `add_bus()` is not used.
2. **Browser autoplay policy** — browsers block all audio until a user gesture (click/keypress). `SplashMenuState.Enter()` checks `OS.has_feature("web")` and shows `%PlayGate` (a centered "Play" button) before the splash sequence. The button press is the gesture that unlocks the AudioContext, so `play_startup()` is guaranteed audible on web.

## How to add a new sound

### One-shot (no parameters)

1. Open `managers/audio_manager.tscn`.
2. Add a child to `Sounds`:
   - Type: `AudioStreamPlayer`
   - Attach `res://utils/custom_audio_middleware/sound_event.gd`
   - Set `stream`, `bus`, `volume_db`, and `unique_name_in_owner = true` so you can fetch with `%YourSound`.
3. In `audio_manager.gd`, add a typed reference and a play method:

   ```gdscript
   var your_sound: SoundEvent

   func _ready():
       ...
       your_sound = get_node_or_null("%YourSound") as SoundEvent

   func play_your_sound():
       your_sound.play()
   ```

### Parameter-driven sound (e.g. speed → low-pass freq, distance → volume)

1. Create a new subclass in `utils/custom_audio_middleware/`:

   ```gdscript
   @tool
   class_name WindSoundEvent extends SoundEvent

   @export var speed_to_volume_db: Curve

   func set_parameter(param_name: String, value: float) -> void:
       if param_name != "Speed":
           return
       volume_db = speed_to_volume_db.sample(clampf(value, 0.0, 1.0))
   ```

2. Add the node in `audio_manager.tscn` using your new script.
3. Expose `update_<your_sound>_<param>(val)` in `audio_manager.gd` that calls `your_sound.set_parameter("Speed", val)`.

### 3D positional sound (other riders)

AudioManager stays the single place sounds are authored. Positional playback borrows from it rather than duplicating nodes:

- `SoundEvent.play_on(player_3d)` copies the event's `stream` + `volume_db` onto an `AudioStreamPlayer3D` and plays it.
- `EngineSoundEvent3D` is the positional engine: it takes the bike's AudioManager `EngineSoundEvent` as a template (`AudioManager.get_engine_sound()`) for streams and base volumes, and the bike definition for curves. Pitch and crossfade math are `EngineSoundEvent`'s static `rpm_to_pitch()` / `crossfade_db()`, so both share one formula.
- `PlayerEntity` carries `%RemoteEngine`, `%RemoteExhaustPop`, `%RemoteExhaustBurble`, `%RemoteCrash`. `play_rider_sound(event, remote_player)` / `stop_rider_sound()` route: the local rider plays the AudioManager event as before (non-positional), anyone else plays on the remote player.
- Tire squeal (`%SquealPlayer`) and the crash grind (`BikeWreck`'s `%WreckGrind`) skip that routing and are positional for every rider, the local one included, so the grind follows the tumbling bike.
- Remote engine RPM comes from the synced `GearingController` state each `_process`. Exhaust pops/burble roll on every peer off the rider's synced throttle, so remote rolls (and flames) don't match the rider's own. Remote crashes play the bone crack positionally; your own crash sounds stay non-positional.

Attenuation is stock `AudioStreamPlayer3D` inverse-distance on those nodes, with `unit_size` (the range heard at full volume, which also delays the distance low-pass) raised on all seven, horn included; tune it in `player_entity.tscn`. Inside `unit_size` inverse-distance gain exceeds 1, so `max_db` tracks each player's current `volume_db`: an adjacent rider is never louder than the sound's authored level. Both engine layers and both player cameras (`TPSCam`, `FPSCam`) use idle-step `doppler_tracking`. Idle, not physics, because rider transforms are interpolated per frame by `TickInterpolator`. A camera without tracking (override cams, garage) hears no doppler.

## Music

Songs live in `audio_manager.tscn` under `Music`, one `SoundEvent` (bus `Music`) per song, split into a container per `AudioManager.MusicType`:

```
AudioManager
├── Sounds
└── Music
    ├── MenuMusic      (%MenuMusic)
    ├── FreeRoamMusic  (%FreeRoamMusic)
    └── EventMusic     (%EventMusic)
```

- **Adding a song:** drop the file in `non_fmod_sounds/Music/<type>/`, add a `SoundEvent` under the matching container. Its `volume_db` is the song's level. Import with loop off, or the song never ends and the playlist never advances.
- **Names:** the pause menu's now-playing shows the stream's filename split on the first `" - "` into artist and title. A file without `" - "` is all title.
- **Playback:** `play_music(type)` crossfades (`music_fade_time`) to a shuffled song from that playlist and is a no-op if it's already playing. Each pass plays every song once before reshuffling. A song ending on its own goes straight to the next; `skip_music_track()` crossfades. `previous_music_track()` walks back through this playlist's history (restarting the song when there is none) and requeues the current one so skip returns to it. `toggle_music_paused()` pauses the current song; any song change resumes. The pause menu's music panel drives all three. Fades are `SoundEvent.fade_in()` / `fade_out()`, which return to the authored `base_volume_db`.
- **Who picks the playlist:** `GamemodeManager` on its state machine's `state_transitioned` (free roam, fuel-up and tutorial → `FREE_ROAM`, every other mode → `EVENT`), and `end_game()` / `SplashMenuState.Exit()` → `MENU`. Transitions run on every peer, so music is local per player and skipping only affects you.
- **Outside `Sounds` on purpose:** `stop_all()` only stops `Sounds`, so match end crossfades to menu music instead of cutting.
- `AudioStreamPlaylist` isn't used: its playback exposes no current track or skip.
- **Ducking:** `set_music_ducked(source, ducked)` tweens the `MusicDuck` bus down by `music_duck_db` while any source holds it. Sources: `SettingsMenuState` (every tab but Audio, so the music slider previews its real level), `GarageUI` (customize menu and free-roam garage, `open()` → `commit()`), and each `PlayerEntity` while its horn plays, any rider, any distance. A sidechain compressor would be the textbook fix for horns, but web's sample playback skips bus effects.

## Things to be aware of

- **Loop on import**: For OGG/MP3 streams, the loop flag lives on the `AudioStream` resource. The `loop` export on `SoundEvent` duplicates the resource at runtime so the shared `.ogg` import isn't mutated process-wide.
- **Volume math**: `SettingsManager` stores linear `[0..1]`; we convert with `linear_to_db()` when applying to the bus. `linear_to_db(0)` returns `-inf` which mutes correctly.
- **No `OS.has_feature("web")` branches in `AudioManager`**: the system works on web with no special cases. The only web-aware code is the splash Play gate, because of the browser gesture requirement.
- **`Sfx` ids are saved as ints** (SfxTask exports, `HornDefinition.sfx`), so append new entries, never reorder. Map each in `_sfx_events` in `_ready`.
- **Horns are positional for everyone, you included**: `PlayerEntity._update_horn()` `play_on`s the horn onto `%HornPlayer` and replays it while `nfx_horn_held`. Every peer runs it off the honker's synced input. See [Skins — Horns](./Skins.md#horns).
- **Adding buses**: edit `default_bus_layout.tres` (or the editor's Audio panel). Then add the key → bus mapping in `VOLUME_SETTING_MAP` and a matching setting in `SettingsManager`.
- **Tuning the RPM curve**: open `audio_manager.tscn`, select `Ninja500Revs`, assign a `Curve` resource to `rpm_to_semitones`. If left null, the default curve is built at runtime.
