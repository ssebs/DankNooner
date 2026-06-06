# Engine Audio v2 — Layered Crossfade System

**Status:** Design / spec (approved 2026-06-06). Not yet implemented.
**Scope:** XSR900 first, local-player-only. Opt-in per bike.

## Goals (from the dev)

These are the concrete problems this system exists to solve, in the dev's own words:

- **"I want the sounds to be good in my game"** — solo dev, no audio engineer. The system has to get a convincing engine sound out of recordings + tuning, not pro mixing.
- **The current approach falls short.** Today's engine sound records *one stable loop and pitch-shifts it by RPM*. That "mostly works but misses lots of the accel vs decel sound differences, and low rpm vs high rpm IRL differences." Those two gaps are the whole reason for v2:
  - **Accel vs decel** — on-throttle (building, loaded) sounds nothing like off-throttle/overrun (engine braking, burble) at the *same* RPM.
  - **Timbre across the rev range** — a bike at 3k isn't just a lower-pitched 9k; the character changes. Pitch-shifting one clip can't reproduce that.
- **Original instinct:** "scrub through the audio track so RPM matches the part of the clip." v2 keeps that instinct but uses *held steady-state tones* instead of a linear sweep, so the sound is clean and loopable (you can't cleanly seek-and-hold inside a sweep recording — it clicks and there's no sustained tone).
- **"I need to be able to tune which sound plays at what RPM for different bikes."** → the RPM→clip mapping is data-driven and inspector-tunable, per bike.
- **"I want to add pops on decel later on. (if decel then hold rpm, pop)."** → designed-in hook now, built later.

## Concept

For opted-in bikes, replace the single pitch-shifted loop with **two sets of steady-state loops** — *accel* (on-throttle) and *decel* (off-throttle/overrun) — each set spanning the rev range as several RPM-keyed loops. Per tick, given `rpm_ratio` (0–1) and `throttle` (0–1):

1. Find the two loops bracketing `rpm_ratio`; **volume-crossfade** them and **lightly pitch-correct** each toward exact RPM (small nudge so timbre stays natural).
2. Do that for both the accel set and the decel set.
3. **Master-crossfade accel ↔ decel by throttle** (smoothed).
4. Idle loop fades in below a low-RPM threshold; the **limiter bang fires as a one-shot** on the `is_rev_limited` rising edge.

```
RPM ratio ───────────────►
idle   2k    4k    6k   redline
 |      |     |     |     |
 [ accel loops ]  ◄─ pitch-nudged + volume crossfade between the 2 bracketing bands
 [ decel loops ]
        ▲
   throttle master-crossfades accel ↔ decel
```

## New Components

### `EngineAudioProfile` (Resource)
Per-bike tunable config — the "which sound at what RPM" knob.

- `idle_stream: AudioStream`
- `limiter_bang_stream: AudioStream`
- `bands: Array` of entries `{ rpm_point: float (0–1), accel_stream: AudioStream, decel_stream: AudioStream }`
- `pitch_correction_semitones: float` — max nudge a band may receive toward exact RPM
- `load_crossfade_speed: float` — smoothing for the accel↔decel transition
- `idle_fade_rpm: float` — RPM ratio below which the idle loop fades in
- *Reserved for decel pops (see below), unused for now:* `pop_streams: Array[AudioStream]`

Tuning "which sound plays at what RPM" = editing `bands` in the inspector. Each bike gets its own `.tres`.

### `LayeredEngineSoundEvent` (Node)
- Builds child looping `AudioStreamPlayer`s from a profile at runtime.
- Owns the per-tick crossfade + pitch-correction math.
- Exposes the **same `play()` / `stop()` / `set_parameter()` interface** as the existing `EngineSoundEvent`, so `AudioManager` drives it uniformly.
- Tracks load state + RPM + stability internally (needed by the future pop emitter).

## Wiring (minimal, follows existing patterns)

- **`BikeSkinDefinition`**: one new `@export var engine_audio_profile: EngineAudioProfile` (nullable). Added to `_copy_from()` and the to/from-dict serialization. **Profile set → layered system; profile null → existing single-loop path, unchanged.** This is the per-bike opt-in.
- **`AudioManager`**: add an XSR900 node (`%Xsr900Revs`, the new script) to `audio_manager.tscn` and `_engine_sounds`. `play_revs()` branches on whether the bike has a profile. `update_revs_rpm` extends to also forward **throttle** and **limiter state** (both already available — `input_controller.nfx_throttle`, `gearing_controller.is_rev_limited`).
- **`player_entity.gd`**: the single local-only call site (~line 299) passes `throttle` + `is_rev_limited` alongside `rpm_ratio`. No new signals needed — `gearing_controller` already exposes all three.

### Data flow
```
gearing_controller (rpm_ratio, throttle, is_rev_limited)
  → player_entity (is_local_client only)
    → audio_manager.update_revs(...)
      → LayeredEngineSoundEvent.set_parameter(...)
```

## Recording Spec (XSR900)

Mic in a consistent spot (near the can or under the tank). Hold each steady 4–6 s:

- **Idle** (~1000 rpm).
- **Accel set** — held under load / on throttle at ~3k, ~5k, ~7k, ~redline-hold.
- **Decel set** — coasting/overrun off-throttle at ~6k, ~4k, ~2k (where the burble lives).
- **Limiter bang** — already captured (`xsr-1st-gear-limiter-bang-converted.ogg`).

Start with ~4 accel + ~3 decel bands; add more only if a transition sounds steppy. Existing `xsr-1st-3rd-pull` / `xsr-1st-gear` clips can supply near-steady slices as a stopgap while re-recording.

## Processing Pipeline (ffmpeg)

Wind reduction is **out of scope for now** (per dev). Per clip, the steps are:

1. **Trim** to the steady portion.
2. **Normalize** loudness (`loudnorm`) so bands sit at matched levels — uneven band volume is what makes crossfades audible.
3. **Find & set loop points** at zero crossings so each loop is click-free.

Exact ffmpeg commands + a loop-point workflow to be produced at implementation time.

## Decel Pops (designed-in, NOT built now)

Reserved cleanly. The layered node already tracks load state + RPM + stability. Later, a small pop emitter reads **"throttle just released AND RPM in a band AND RPM roughly held"** → fires pop one-shots from `EngineAudioProfile.pop_streams` at intervals. No work now beyond the reserved `pop_streams` field and keeping load/RPM state accessible.

## Verification (dev runs the project)

Audio can't be meaningfully unit-tested. Plan:

- **Editor `@tool` audition panel** on the layered node — RPM + throttle sliders that play the live crossfade in-editor (middleware is already `@tool`-friendly). Lets the dev tune without rebuilding.
- **In-game debug overlay** via `DebugUtils` showing active bands + their volumes.

## Out of Scope (future, separate work)

- Audible **remote bikes** (3D positional engine sound, per-player RPM/throttle network sync, LOD). Engine audio is local-player-only today; v2 keeps it that way.
- Decel **pops/crackle** (hook reserved above).
- Wind/noise reduction on recordings.
- Porting Ninja500 / Grom to the layered system (they keep the single-loop path until each gets a profile).
