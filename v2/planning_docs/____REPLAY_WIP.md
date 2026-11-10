# Replay Studio (WIP)

Theater-mode footage capture for trailers. Play normally, record, then open the recording in a
separate scene, fly a camera around, key camera moves, cut clips, and render with Movie Maker.

## Intent

- Trailer footage from real gameplay, shot from angles / speeds you can't get live.
- Dev tool, not a player feature. Never ships in menus.

## Goals

- Record the local rider, other players, traffic, and NPC racers while playing.
- Playback scene: free fly camera, timeline (play / pause / scrub / skip), camera keyframes,
  basic cutting (in/out clips), per-clip playback speed (slow-mo).
- Render the cut to video via Godot's Movie Maker at a locked framerate.

## Non-goals

- Exact reproduction. Movement must match; particles / ragdolls only need to exist and look right.
- Animals (not used), audio (added in the edit), HUD, pickups / item hit effects.
- Scrubbing backwards through a ragdoll looking correct (see Crashes).
- Camera FOV keys, easing curves per key, transitions between clips. Hard cuts only.

## Anti-goals

- Touching `PlayerEntity` / NPC simulation code to make playback work. Recording is read-only
  observation; playback never instantiates `PlayerEntity`, `NPCRiderEntity`, or netfox.
- A second animation pipeline. Playback reuses `RiderVisual` (already shared by NPCs, garage,
  `TrickDemo`).

## How it works (decided)

### Recording: capture visuals, not sim state

Record what is *drawn*, sampled in `_process`, not netfox state. This sidesteps resimulation,
authority, and AI entirely: playback is "set transforms on a `RiderVisual`".

Per rider (player or NPC), per sample:
- Entity `global_transform`.
- Local transforms of `IKTargets`, `BikeSkin`, and the IK markers (`ButtTarget`, `ChestTarget`,
  `HeadTarget`, hand / foot targets, arm / leg magnets). Names already match between
  `player_entity.tscn` (`VisualRoot/IKTargets/...`) and `rider_visual.tscn` (`IKTargets/...`).
  Note `BikeSkin` is under `IKTargets` in the player but a sibling in `RiderVisual`, so record it
  relative to the visual root.
- Wheel spin speed (for `rotate_wheels`).
- Particle / VFX flags: boost trail emitting, crash state. Others (exhaust pops, sparks,
  skidmarks) are the builder's call based on what's cheap to drive from a flag.

Per car NPC: entity transform + wheel speed.

Per entity, once on first appearance: entity id, kind (player / NPC rider / car), skin
definitions + colors. Entities appear / disappear mid-recording (traffic recycling), so the file
holds spawn / despawn events keyed by id.

Header: `LevelManager.LevelName` of the level, so playback instantiates it from
`possible_levels`.

### Recording trigger

`@export var recording: bool` on the `main_game` root (`ManagerManager`, already `@tool`).
Flip it in the **Remote** scene tree while the game runs; the setter starts / stops and writes
the file. (An inspector tool button can't reach the running game; a changed export value can.)
A recorder node owns the logic; `ManagerManager` only forwards the toggle.

### Playback scene (separate scene, like `scripts/key_art/`)

- Load a recording file (export path), instantiate the level, spawn one `RiderVisual` (or car
  skin) per entity, apply skins.
- Each frame: find the two samples around the playhead, interpolate transforms, apply. Toggle
  emitters from flags. Spawn / free visuals on spawn / despawn events.
- No managers from `main_game`; the scene stands alone.

### Crashes

On a crash-start edge, start the ragdoll the way `TrickDemo.crash()` does
(`character_skin.start_ragdoll(impulse)`); on crash end, rebuild skins as `TrickDemo` does. The
ragdoll is re-simulated live, so it won't match the original and won't scrub backwards
correctly; seeking resets it.

### Edit UI

- **Fly camera:** Godot-editor freelook. Hold RMB to look, WASD move, Q/E down/up, Shift fast,
  scroll changes speed.
- **Timeline bar:** playhead, scrub by click/drag, camera key markers, clip ranges.
- **Hotkeys:** Space play/pause, Left/Right skip, K key camera at playhead, Delete removes the
  nearest key, I / O set clip in / out, Ctrl+S save edit.
- **Camera keys:** position + rotation at a recording time. Between keys: smooth position spline,
  slerped rotation. With zero keys, the camera stays where you flew it. While playing with keys,
  the camera follows the keys; touching RMB takes manual control until next play.
- **Clips:** ordered list of (in, out, speed). Speed is playback rate for that clip (0.25 =
  slow-mo).
- Edit data (keys, clips) saves next to the recording as its own file, so the recording stays
  untouched.

### Render

Enable Movie Maker in the editor and run the playback scene with `render_on_start` checked: it
plays every clip in order through the camera keys with no UI, then quits. Movie Maker's fixed
fps makes slow-mo and heavy scenes smooth.

## Constraints

- File size: a few minutes of traffic-heavy play must stay manageable. Expect to sample below
  render rate (e.g. 30 Hz) and interpolate, write via `FileAccess.open_compressed`, and possibly
  skip NPCs far from every player. Builder picks the numbers.
- Recording must not hitch gameplay (no per-frame disk writes of big blobs; buffer, write on stop
  or in chunks).
- Works solo and as host. Clients recording is the builder's call (they see the same visuals).

## Calls I made (Claude's, not agreed yet)

- Record drawn transforms instead of netfox state (changed from the first pitch: avoids running
  `PlayerEntity` with no peer).
- Files go in `user://replays/` (`<timestamp>.replay` + `<timestamp>.edit`).
- Scene lives in `scripts/replay_studio/`.
- Per-clip speed instead of keyed speed ramps.
- Hotkey set above.

## Left to the builder

- Sample rate, encoding, NPC distance cull.
- Which VFX beyond boost trail / crash get flags.
- Timeline UI look.
- Verify the IK markers fully determine the player's pose. If `AnimationController` writes bones
  directly anywhere (beyond IK), record those too.
- How the recorder finds entities (groups / managers) — reuse existing groups (`Racers`, etc).
