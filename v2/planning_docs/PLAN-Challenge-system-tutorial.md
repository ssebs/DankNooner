# PLAN — Challenge System (Sprint Phase 3)

In-world, opt-in trick challenges. Skate-style. Replaces forced HUD-text tutorials.

## Goal

Players discover trick challenges by riding around the world. Roll into a marker → a 2D billboard speech bubble explains the challenge → complete it → get rewarded (visual feedback for now, currency/unlocks later). Tricks become learnable through *playing*, not through a forced tutorial flow.

This also doubles as scaffolding for the future **Trick Battle** gamemode — same trick-detection task type will power its scoring.

## Out of scope

- NPCs of any kind (no characters, no dialog system) — text bubble billboards only
- Trick Battle / Score Attack gamemode itself — next sprint
- Tricks-matter-in-race integration — next sprint
- Persistent rewards / currency / unlock economy — next sprint (use a transient "challenge complete" toast for now)
- New trick animations — Phase 2 enables them; this sprint uses what exists
- Replacing the existing `TutorialGameMode` — leave it alone; challenges are a separate, parallel system
- Designing more than 3-5 starter challenges (human picks specifics in editor)

## Design

### What a "Challenge" is

A scene placed in the world. Has:
- A trigger volume (player enters → challenge offered)
- A 2D billboard with speech bubble showing the challenge text
- A success condition (do trick X within time Y, in zone Z, etc.)
- A success effect (toast, sound, optional level-state change)

Architecturally it's a lightweight cousin of `EventStartCircle` + a single-task runner. Reuses existing primitives.

### Reused components

- `CheckPointMarker` — for "go here" sub-objectives
- `SequentialTaskRunner` / `ConcurrentTaskRunner` — orchestrate multi-step challenges
- `GameModeTask` base — for the new `PerformTrickTask` (see below)
- `EventStartCircle` pattern — `ChallengeStartCircle` is a near-copy that doesn't change gamemode
- `TrickController.trick_started` / `trick_ended` signals — input to `PerformTrickTask`
- `RaceTask`'s per-peer progress tracking pattern — copy the dict-on-task approach

### New components

#### 1. `SpeechBubble` (2D billboard)
- `Sprite3D` with `billboard = ENABLED` carrying a cutout/balloon texture
- `Label3D` for the text (or a sub-`SubViewport` if richer formatting is needed — start with `Label3D`)
- Exports: `text: String`, `tail_target: Node3D` (optional, future)
- Show/hide via `visible`. No animation in v1; can add a pop-in tween later.
- Lives under: `managers/gamemodes/gamemodeobjects/speech_bubble.gd` + `.tscn`
- Multiplayer: visible per-peer based on proximity; no sync needed (purely visual)

#### 2. `PerformTrickTask` (new `GameModeTask`)
- Exports:
  - `required_trick: TrickController.Trick`
  - `min_duration: float = 0.0` (e.g. wheelie for 3 seconds; 0 = any duration)
  - `success_zone: Area3D = null` (optional — trick must end inside this volume)
- Per-peer state dict (mirrors `RaceTask._peer_progress`):
  `peer_id → { trick_active, start_ms, completed }`
- Connects to `TrickController.trick_started` / `trick_ended` on each entering player.
- `check()` returns true for a peer when their `completed` flag is set.
- File: `managers/gamemodes/tasks/perform_trick_task.gd`

#### 3. `ChallengeStartCircle` (extends `EventStartCircle` or near-copy)
- Same trigger pattern as `EventStartCircle` but:
  - **Does NOT change the gamemode** (free roam stays free roam)
  - Runs its task runner in the background; player keeps riding normally
  - On `all_completed`, shows a toast ("Challenge complete!") and hides the speech bubble
  - On player exit (leaves trigger before completing), aborts the runner gracefully
- Owns a `SpeechBubble` child that activates on entry and updates as steps progress
- File: `managers/gamemodes/gamemodeobjects/challenge_start_circle.gd` + `.tscn`

#### 4. `ChallengeHUD` (or reuse `TutorialHUD`)
- Recommend **reuse `TutorialHUD`** with a "challenge mode" toggle that suppresses the heavy tutorial framing (no step counter, no big banner — just the progress text).
- If `TutorialHUD` reuse turns out to be awkward, build a small dedicated `ChallengeHUD` — decide during impl.

### Scene shape (example)

```
ChallengeStartCircle  (in world, near a ramp)
├── Trigger (Area3D)
├── SpeechBubble  (text: "Land a heel clicker off this ramp!")
└── SequentialTaskRunner
    └── PerformTrickTask
        ├── required_trick = HEEL_CLICKER
        └── success_zone = LandingZone (Area3D under same parent)
```

Human places challenges directly in level scenes.

### Multiplayer behavior

- Each peer independently triggers / completes challenges (per-peer progress in the task).
- Speech bubbles render locally per peer (no network cost).
- Toast on complete is local-only.
- Runner state lives on host; per-peer task state already follows the `RaceTask` pattern.

## Starter challenges (human picks 3-5 in editor)

The human will choose. Reasonable starting points (all use existing tricks):
- "Hold a wheelie for 5 seconds"
- "Stoppie into this zone"
- "Land a heel clicker off the ramp"
- "Pop a high chair while airborne"
- "Two-left-feet for 3 seconds"

## Verification

- Solo: ride into each challenge, complete it, see the success toast.
- Solo: ride into a challenge and fail it (leave the area / crash). Bubble disappears cleanly.
- Co-op (2 peers): both can trigger the same challenge independently; both can complete; one completing doesn't affect the other's progress.
- Crash mid-challenge: respawn correctly; challenge resets if you re-enter.
- Challenges don't interfere with free-roam gameplay (no input lock, no camera change).

## Sequencing

1. Build `SpeechBubble` standalone — drop in a test level, confirm billboarding + text work.
2. Build `PerformTrickTask` — test against existing `TutorialGameMode` first (cheaper than building a new gamemode-less runner). Wire it to a trigger volume and confirm it detects a wheelie.
3. Build `ChallengeStartCircle` by adapting `EventStartCircle`. Make sure it runs the task runner WITHOUT swapping gamemodes.
4. Wire `SpeechBubble` to the `ChallengeStartCircle` (show on enter, hide on complete/abort).
5. Add 3-5 challenges to the existing test level by hand.
6. Multiplayer pass — two peers, verify per-peer independence.
7. Polish: success toast, sound, brief bubble pop-in tween.

## Risks

- **`EventStartCircle` is tightly coupled to gamemode-switching.** Extracting "run a runner without changing gamemode" may surface assumptions in `GamemodeManager`. If extraction proves painful, accept duplication and write `ChallengeStartCircle` as a parallel implementation.
- **`PerformTrickTask` needs to know when a trick is "complete enough"** — wheelie has duration, heel_clicker is one-shot. The `min_duration` export handles duration tricks; instantaneous tricks fire on `trick_started` immediately. Confirm both modes work.
- **Per-peer state cleanup** when a player leaves the trigger before completing — make sure the dict entry is removed, not leaked.
- **Speech bubble readability** — Label3D depth, scaling with distance, occlusion. Iterate visually; not worth over-planning here.

## Future hooks (do not build now)

- Reward currency / unlocks → wire `all_completed` to `SaveManager`
- Challenge chains (do A, then B, then C) → already supported by `SequentialTaskRunner`
- Trick Battle mode → instantiates `PerformTrickTask` repeatedly with a timer
- "Tricks matter in race" → race's `RaceTask` instantiates a `PerformTrickTask` per checkpoint segment for bonus scoring
