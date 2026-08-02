# Bugfix + Pattern-Cleanup Implementation Plan (2026-08-01)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the multiplayer regressions on TODO.md's Active list (traffic host-only, join speed-cap, bot DNF, Terrain3D fall-through, ramp crash loop) and refactor the AI-written systems back onto the project's original patterns (controllers own synced state, request-based late-join, guarded RPC surface), then bring the docs back in line with the code.

**Architecture:** Three phases. Phase 1 (bug fixes) is DONE and user-verified — see its completion stanza below; do not redo it. Phase 2 refactors (RPC authority, late-join contract, BoostController, NPC smoothing). Phase 3 updates docs for the Phase 2 deltas. Human-test gates between phases — this project has no automated tests and only the human runs the game.

**Tech Stack:** Godot 4.7 / GDScript, netfox (RollbackSynchronizer/TickInterpolator), Terrain3D GDExtension, godot-road-generator.

## Global Constraints

- **NEVER run `git` or `gh` commands** (CLAUDE.md). At each "Commit point" step, STOP and ask the user to review + commit.
- **NEVER edit `planning_docs/TODO.md`** — the user owns it. Report status in chat.
- **Only the human runs the game.** Verification per task = LSP diagnostics clean (`mcp__ide__getDiagnostics`) against `.gdlintrc` (watch `class-definitions-order`). Gameplay verification happens at the phase gates via the human checklists.
- Use `DebugUtils.DebugMsg()` for all debug output. Tabs for indentation. Match each file's local style.
- Fail loudly: no `if x == null: return` without a comment explaining why null is expected.
- Doc updates list tunables by **name + behavior only, never current values**.
- When editing `.tscn` files: text edits only, minimal diffs. Omit `unique_id=` on new nodes (the editor assigns one on next save). New script `ext_resource` entries may omit `uid=` — Godot re-adds it.
- Reuse existing signals/patterns before adding new ones. Every new method in this plan exists because no current API covers it — do not add more beyond what's specced.

## Verified facts this plan relies on (do not re-derive)

- `GamemodeManager.start_game` suspends on `await RenderingServer.frame_post_draw` (gamemode_manager.gd:74); RPCs arriving during the await are processed **before** `spawn_level` runs on that peer.
- `_sync_game_to_late_joiner` ships only `level_name` + `gamemode`; `latespawn_player` re-sends players only — nothing re-sends NPCs.
- `StateMachine.clear_current_state()` **does** run `Exit()` (state_machine.gd:63); `_transition_to` early-returns on same-state.
- `SequentialTaskRunner.stop()` **clears `_player_states` and nulls `task._runner`** — results code must not read runner state after `stop()`. RaceTask's checkpoint signals stay connected after stop, and NPC `_advance` never touches `_runner`, so NPC scoring continues during the results countdown.
- `RollbackSynchronizer` lists in player_entity.tscn:1159-1160 are correct/complete today (state list now also carries `%GearingController:is_rev_limited`, added post-Gate-A). `%MovementController` / `%GearingController` / `%TrickController` / `%HUDController` / `%InputController` all have `unique_name_in_owner = true`.
- NPCs sync via plain `MultiplayerSynchronizer` (server authority), **no** TickInterpolator. `NPCRiderEntity` id names: traffic ids start at -1000, race ids at -1.
- Terrain3D collision defaults to camera-tracked dynamic mode; `camera_controller.gd:277` hands it the local player camera via the `Terrain3D` group. API (GDExtension): `terrain.collision.mode`, enum constants on `Terrain3DCollision` (seen in terrain3d_demo/src/CodeGenerated.gd:75).
- netfox perf monitors exist (addons/netfox/network-performance.gd:4-14), e.g. `&"netfox/Rollback ticks simulated"`.
- localization.csv header: `keys,en,es`.
- Boost/combo var readers (grep-verified): movement_controller, player_entity, trick_controller, hud_controller, trick_manager, camera_controller, input_controller, hud_elements/combo_counter, hud_elements/boost_gauge.

---

# PHASE 1 — DONE (completed + user-verified 2026-08-01)

All seven bug-fix tasks landed, were review-gated, and passed the Gate A playtest. Do NOT re-implement them. What shipped:

1. Traffic sync: client `_accept_spawns` gate + `request_traffic_sync()` pull / `reset_local_traffic()` in NPCTrafficManager; hooks in free-roam + street-race Enter/Exit else-branches; spawn/despawn RPCs idempotent.
2. Race-bot late-join resync: `NPCRaceManager.sync_npcs_to_peer(peer_id)` (`_defs` payload store), called from both race gamemodes' `_on_player_latejoined`.
3. Terrain3D: server forces `terrain.collision.mode = Terrain3DCollision.FULL_GAME` in `LevelDefinition._ready` (enum verified against the DLL).
4. Live race results: `RaceTask.get_completion_time_ms/has_racer`, `ResultsHUD.rpc_update_rows` (+ remove_child-before-queue_free), 1 Hz refresh during countdown, `RACE_RACING` locale key; human rows cached before `runner.stop()`. Duplicated in BOTH race gamemodes.
5. Ramp crash respawn: server-side flat-ground breadcrumbs in FreeRoamGameMode; `_ground_normal_at(player)` excludes the player's RID and masks to layer 1 (self-hit/ragdoll-bone poisoning was a review-caught Critical).
6. Netfox debug overlay in HUDController (debug builds, local client, `has_custom_monitor` guard).
7. Post-gate fixes: `%GearingController:is_rev_limited` added to RollbackSynchronizer state_properties (rollback-mutated var, gate for power output — was rubberbanding gear shifts); null-peer guard in `NPCRaceManager._physics_process` (menu error spam).

Known deferred minors (final review triages): `_results_countdown` not cleared in race Exit(); `npc_race_manager.gd` `_peer_progress` read replaceable with `get_completion_time_ms`; pre-existing gdformat disagreement on hud_controller's `tr().format()`; sand (layer 20) crash sites read as void → breadcrumb respawn (accepted).

Phase 1 docs updates were applied 2026-08-01 (CLAUDE.md, Architecture.md, code-review triage) — Task 12 below now covers ONLY the Phase 2 deltas.

---

# PHASE 2 — PATTERN REFACTORS

### Task 8: RPC authority guards (SpawnManager + GamemodeManager)

Closes the April review's "authority holes", which have grown to ~8 `any_peer` RPCs.

**Files:**
- Modify: `managers/spawn_manager.gd`
- Modify: `managers/gamemodes/gamemode_manager.gd`
- Modify: `menus/pause_menu/pause_menu_state.gd:82-84`
- Modify: every direct `_rpc_transition_gamemode.rpc(` caller (grep; known: `types/street_race`, `types/road_race` `_return_to_free_roam`, plus `types/tutorial` and `types/challenge`)

**Interfaces:**
- Produces: `SpawnManager.request_respawn()` (client-callable). All broadcast RPCs reject non-server senders.

- [ ] **Step 1: SpawnManager sender guard helper** (private region, above the RPCs):

```gdscript
## True when the executing RPC came from the server or a local call — sender id is
## the local peer's own id for call_local execution (1 on the host) and 1 for
## server-sent RPCs. The broadcast RPCs below stay any_peer only because the server
## must call_local them; this closes them to clients.
func _sender_is_server() -> bool:
	return multiplayer.get_remote_sender_id() <= 1
```

Add `if !_sender_is_server(): return` as the first line of: `respawn_player`, `crash_player`, `respawn_player_at`, `respawn_player_in_place`, `set_respawn_point`, `reset_respawn_point`.

Caution: `get_remote_sender_id()` inside a call_local execution on a CLIENT returns that client's own id (>1) — that's exactly the block we want, but it means any legit client-side caller must be converted (next steps). Grep for `.rpc(` on all six names and confirm every remaining caller runs server-side; convert or wrap any that don't.

- [ ] **Step 2: Client request path**:

```gdscript
## Client-callable: ask the server to respawn YOU (pause-menu button). The server
## derives the target from the sender — a client can never respawn someone else.
@rpc("any_peer", "call_local", "reliable")
func request_respawn():
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# sender == 1 covers both the host's local call and (impossibly) server-sent.
	respawn_player.rpc(sender if sender > 1 else 1)
```

`pause_menu_state.gd:_on_respawn_pressed` becomes:

```gdscript
func _on_respawn_pressed():
	spawn_manager.request_respawn.rpc_id(1)
	_on_resume_pressed()
```

- [ ] **Step 3: GamemodeManager guards.**
  - `start_game`: first line `if multiplayer.get_remote_sender_id() > 1: return` with comment `# Only the server starts matches — a client RPCing this is misbehaving.`
  - `_sync_game_to_late_joiner`: change decorator `@rpc("any_peer", "reliable")` → `@rpc("reliable")` (authority mode — the server owns manager nodes, and only the server sends it).
  - `_request_late_spawn`: after the is_server guard add `if multiplayer.get_remote_sender_id() not in [0, peer_id]: return` with comment `# A peer may only request its own late spawn.`

- [ ] **Step 4: One entry point for gamemode transitions.** Grep `_rpc_transition_gamemode.rpc(`. Each direct call site runs server-side already; replace with the guarded entry point, e.g. street/road race:

```gdscript
func _return_to_free_roam():
	gamemode_manager.change_gamemode(GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id())
```

(direct call, not `.rpc_id(1, …)` — these sites are already on the server and `change_gamemode` re-broadcasts). Apply the same shape to the tutorial/challenge sites, preserving their target-mode + circle-path arguments.

- [ ] **Step 5: Verify** — diagnostics clean everywhere; grep confirms zero remaining direct `_rpc_transition_gamemode.rpc(` calls outside gamemode_manager.gd.

- [ ] **Step 6: Commit point.**

### Task 9: Late-join contract on GameModeType

The April review's contract, minimally: modes declare late-joinability and (optionally) ship state. Fixes the mid-race late-join **client crash** (null `ctx.event_start_circle`) by landing late joiners in free roam instead.

**Files:**
- Modify: `managers/gamemodes/gamemode.gd` (base `GameModeType`)
- Modify: `managers/gamemodes/types/free_roam/free_roam_gamemode.gd`
- Modify: `managers/gamemodes/gamemode_manager.gd:191-230`

- [ ] **Step 1: Base contract** in `gamemode.gd`:

```gdscript
## Whether a late joiner can be dropped straight into this mode. Modes needing
## mid-match context (races: start circle + runner state) return false; the late
## joiner free-roams the level instead and syncs up at the next mode change.
func is_late_joinable() -> bool:
	return false


## Ship/restore mid-match state to late joiners. Base: nothing to ship.
func serialize_state_for_late_joiner() -> Dictionary:
	return {}


func apply_state_from_host(_state: Dictionary) -> void:
	pass
```

FreeRoamGameMode override:

```gdscript
func is_late_joinable() -> bool:
	return true
```

- [ ] **Step 2: GamemodeManager ships it.** `_on_client_connection_succeeded`:

```gdscript
	if match_state == MatchState.IN_GAME:
		# Modes that can't take a late joiner mid-flight (races) sync the joiner
		# into free roam on the same level instead — they still spawn and ride.
		var sync_mode := current_game_mode
		if !_gamemode_map[current_game_mode].is_late_joinable():
			sync_mode = GameModeType.Kind.FREE_ROAM
		_sync_game_to_late_joiner.rpc_id(
			peer_id,
			current_level_name,
			sync_mode as int,
			_gamemode_map[sync_mode].serialize_state_for_late_joiner()
		)
```

`_sync_game_to_late_joiner` gains the param and applies it after the state change:

```gdscript
@rpc("reliable")
func _sync_game_to_late_joiner(
	level_name: LevelManager.LevelName,
	gamemode: GameModeType.Kind = GameModeType.Kind.FREE_ROAM,
	state: Dictionary = {}
):
	# ... existing body through state_machine.request_state_change ...
	_gamemode_map[current_game_mode].apply_state_from_host(state)
	# ... existing _request_late_spawn call ...
```

- [ ] **Step 3: Block race hijacks.** A late joiner free-roaming during a server-side race can drive into an event circle and request a mode change, nuking the live race. In `change_gamemode`, after the is_server guard:

```gdscript
	# A race is running — only a return to free roam (host cancel / race end) may
	# interrupt it. Blocks a free-roaming late joiner starting a second event.
	if (
		!_gamemode_map[current_game_mode].is_late_joinable()
		and gamemode != GameModeType.Kind.FREE_ROAM
	):
		return
```

- [ ] **Step 4: Verify** — diagnostics clean. Note in chat for the user: late joiner in free roam sees no race HUD while the race runs; when the race ends, everyone transitions to FREE_ROAM — the joiner's same-state transition is a no-op by design.

- [ ] **Step 5: Commit point.**

### Task 10: BoostController — boost state off PlayerEntity, combo state onto TrickController

The netfox constraint is *when* the code runs (rollback tick), not *where the state lives*. Restore the "controllers own their domain, synced as `%Controller:var`" pattern.

**Files:**
- Create: `player/controllers/boost_controller.gd`
- Modify: `player/player_entity.gd` (remove 9 vars; wire controller; respawn ordering)
- Modify: `player/player_entity.tscn` (new node, state_properties, node_paths)
- Modify: `player/controllers/movement_controller.gd` (delete `_boost_calc` + consts; re-point reads)
- Modify: `player/controllers/trick_controller.gd` (own combo vars; write boost via controller)
- Modify: `player/controllers/hud_controller.gd`, `player/controllers/camera_controller.gd`, `player/controllers/input_controller.gd`, `managers/trick_manager.gd`, `player/hud_elements/combo_counter.gd`, `player/hud_elements/boost_gauge.gd` (re-point reads)

**Interfaces:**
- Produces: `BoostController` with synced vars `boost_amount`, `boost_burn_target`, `boost_burn_rate`, `boost_prev_held`, `is_boosting`; consts `BOOST_SEGMENTS`, `BOOST_SEGMENT_SECS`, `BOOST_FULL_BURN_SECS`, `BOOST_ACCEL_MULT`, `BOOST_SPEED_MULT`; methods `on_movement_rollback_tick(delta)`, `apply_crash_void(earned: float)`, `do_reset()`.
- `TrickController` gains synced vars `combo_time`, `combo_grace`, `combo_multiplier`, `combo_boost_earned` (moved from PlayerEntity, semantics unchanged).
- `PlayerEntity` gains `@export var boost_controller: BoostController` (+ configuration warning).

- [ ] **Step 1: Create `player/controllers/boost_controller.gd`.** Move `MovementController._boost_calc` (movement_controller.gd:327-358) and the five `BOOST_*` consts (movement_controller.gd:69-73) here verbatim, de-prefixing `pe.` for the vars that now live on this controller and keeping `player_entity.is_crashed` / `input_controller.nfx_boost_held` reads. Preserve every existing comment:

```gdscript
@tool
## Owns the boost meter: commit-on-press burn mechanics + the synced meter state.
## Earned by TrickController's combo accrual, spent here, banked by TrickManager.
## Runs inside the rollback tick — see planning_docs/ComboAndBoost.md.
class_name BoostController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var trick_controller: TrickController

# (BOOST_* consts moved from MovementController, comments included)

# Netfox synced state — listed in player_entity.tscn's RollbackSynchronizer.
var boost_amount: float = 0.0
var boost_burn_target: float = -1.0
var boost_burn_rate: float = 0.0
var boost_prev_held: bool = false
var is_boosting: bool = false


## Called FIRST from PlayerEntity._rollback_tick — ahead of the crash bail-out so a
## crash mid-boost cancels the burn (and its camera FX) instead of latching it.
func on_movement_rollback_tick(delta: float):
	# (moved _boost_calc body)


## A crash voids only what the in-progress combo earned — boost banked by earlier
## completed combos survives. Called from PlayerEntity._apply_respawn_state BEFORE
## the do_reset loop clears trick_controller.combo_boost_earned.
func apply_crash_void(earned: float):
	boost_amount = maxf(boost_amount - earned, 0.0)


## Called from player_entity.gd's do_respawn. boost_amount deliberately survives —
## banked boost is yours across respawns; only the active burn resets.
func do_reset():
	boost_burn_target = -1.0
	boost_burn_rate = 0.0
	boost_prev_held = false
	is_boosting = false
```

Plus the standard `_get_configuration_warnings()` for the three exports.

- [ ] **Step 2: Move combo vars to TrickController.** Cut `combo_time`, `combo_grace`, `combo_multiplier`, `combo_boost_earned` (with their doc comments, player_entity.gd:106-115) into trick_controller.gd's var block. In `_accrue_combo`, replace `player_entity.combo_*` with `combo_*` and `player_entity.boost_amount` with `boost_controller.boost_amount` (add `@export var boost_controller: BoostController` + config warning). Extend TrickController's `do_reset()` to zero all four combo vars.

- [ ] **Step 3: PlayerEntity.** Delete the nine vars (keep `is_crashed`). Add the export + wiring. `_rollback_tick` order becomes:

```gdscript
	# Boost first — ahead of every controller AND evaluated even while crashed, so a
	# crash mid-boost cancels the burn (this was previously _boost_calc's first-line
	# position inside MovementController's tick).
	boost_controller.on_movement_rollback_tick(delta)
	movement_controller.on_movement_rollback_tick(delta)
	gearing_controller.on_movement_rollback_tick(delta)
	trick_controller.on_movement_rollback_tick(delta)
	crash_controller.on_movement_rollback_tick(delta)
```

`_apply_respawn_state` — the boost/combo lines collapse to:

```gdscript
	# Void order matters: read the combo's claim before TrickController.do_reset
	# (in the loop below) clears it.
	boost_controller.apply_crash_void(trick_controller.combo_boost_earned)
	is_crashed = false
	for child in controllers_node.get_children():
		...
```

(the burn/combo field resets now live in the two controllers' `do_reset`, which the existing loop already calls — verify BoostController sits under `_Controllers` so the loop reaches it).

- [ ] **Step 4: player_entity.tscn.**
  1. Add ext_resource near the other controller scripts: `[ext_resource type="Script" path="res://player/controllers/boost_controller.gd" id="11_boost"]`
  2. Add node after the InputController block under `_Controllers`:

```text
[node name="BoostController" type="Node" parent="_Controllers" node_paths=PackedStringArray("player_entity", "input_controller", "trick_controller")]
unique_name_in_owner = true
script = ExtResource("11_boost")
player_entity = NodePath("../..")
input_controller = NodePath("../InputController")
trick_controller = NodePath("../TrickController")
```

  (match the sibling nodes' NodePath style exactly — read a neighbor block first.)
  3. Rewrite line 1159's `state_properties`: remove `":boost_amount", ":boost_burn_target", ":boost_burn_rate", ":boost_prev_held", ":combo_time", ":combo_grace", ":combo_boost_earned", ":combo_multiplier", ":is_boosting"`; add `"%BoostController:boost_amount", "%BoostController:boost_burn_target", "%BoostController:boost_burn_rate", "%BoostController:boost_prev_held", "%BoostController:is_boosting", "%TrickController:combo_time", "%TrickController:combo_grace", "%TrickController:combo_boost_earned", "%TrickController:combo_multiplier"`. `:global_transform`, `:velocity`, `:up_direction`, `:is_crashed` and the existing `%MovementController`/`%GearingController` entries stay.
  4. Root `PlayerEntity` node: add `"boost_controller"` to its `node_paths` array and `boost_controller = NodePath("_Controllers/BoostController")` to its properties.
  5. TrickController and HUDController node entries: extend their `node_paths` + properties with `boost_controller = NodePath("../BoostController")` (TrickController) / whatever export name Step 5 adds (HUDController).

- [ ] **Step 5: Re-point every reader.** Run: `grep -rn "boost_amount\|is_boosting\|combo_multiplier\|combo_time\|boost_burn\|boost_prev_held\|combo_grace\|combo_boost_earned" --include="*.gd" player/ managers/ menus/ utils/` — fix ALL hits outside boost_controller/trick_controller:
  - movement_controller.gd: delete `_boost_calc` + the 5 consts + the `_boost_calc(delta)` call; `_speed_calc` reads become `player_entity.boost_controller.is_boosting`, `BoostController.BOOST_ACCEL_MULT`, `BoostController.BOOST_SPEED_MULT`.
  - input_controller.gd:114: `player_entity.is_boosting` → `player_entity.boost_controller.is_boosting`.
  - camera_controller.gd (2 hits), hud_controller.gd (7 hits, add a `boost_controller` export wired in tscn per Step 4.5), trick_manager.gd (4 hits → `player.trick_controller.*` / `player.boost_controller.*`), combo_counter.gd + boost_gauge.gd (1 hit each — follow how HUD pushes values into them).
  - The grep must end with zero hits referencing these vars via `player_entity.` or bare `pe.`.

- [ ] **Step 6: Verify** — diagnostics clean on every touched file; re-run the Step 5 grep; confirm state_properties count in tscn equals old count (nothing dropped, only re-pathed).

- [ ] **Step 7: Commit point** — this task is its own commit ("refactor: BoostController owns boost state, TrickController owns combo state").

### Task 11: NPC transform smoothing (the "laggy NPCs" TODO item)

**Files:**
- Modify: `entities/npc/npc_rider_entity.gd`
- Modify: `entities/npc/npc_rider_entity.tscn` (SceneReplicationConfig)

- [ ] **Step 1: Read first.** Read `npc_rider_entity.gd` fully and the tscn's `SceneReplicationConfig` sub-resource to see exactly which properties replicate today (expected: `.:transform` or `.:global_transform` + `.:npc_state`).

- [ ] **Step 2: Indirect the transform.** Add:

```gdscript
## Written by the server each physics tick and replicated; clients lerp toward it so
## replication-rate updates don't strobe at render framerate.
var sync_transform: Transform3D
## Distance beyond which a client snaps instead of lerping (teleport/recovery).
const NET_SNAP_DISTANCE: float = 25.0
const NET_LERP_SPEED: float = 12.0
```

Server: at the end of `_physics_process` (or the equivalent movement tick the file uses): `sync_transform = global_transform`. Also set it inside `teleport_to` so recoveries snap on the wire immediately.

Client: in `_process`:

```gdscript
	if multiplayer.multiplayer_peer != null and !multiplayer.is_server():
		if global_position.distance_to(sync_transform.origin) > NET_SNAP_DISTANCE:
			global_transform = sync_transform
		else:
			var w := 1.0 - exp(-NET_LERP_SPEED * delta)
			global_transform = global_transform.interpolate_with(sync_transform, w)
```

Guard the initial state: initialize `sync_transform = global_transform` at the end of `_ready` so clients don't lerp from the origin.

- [ ] **Step 3: Swap the replication property** in the tscn's SceneReplicationConfig: replace the transform property entry with `.:sync_transform` (same replication mode the old entry used); `npc_state` entry stays.

- [ ] **Step 4: Verify** — diagnostics clean; confirm no other code reads the replicated transform property name you removed.

- [ ] **Step 5: Commit point.**

## GATE B — human test checklist (STOP; ask the user to run)

1. Full boost regression, MP host + client: earn combo (wheelie chain), meter fills; tap-to-burn one segment; full-meter long burn; crash mid-combo voids only the in-progress earnings; respawn keeps banked boost; forced auto-shift during boost; HUD gauge + combo counter + camera FX all live on the client.
2. Pause-menu respawn button works for host AND client (now routed via `request_respawn`).
3. Late join during a running street race: joiner lands in free roam on the level, spawns, no client crash, race unaffected; joiner cannot start an event circle while the race runs; when the race ends everyone is in free roam together.
4. Traffic NPCs look smooth on the client (no 30 Hz strobing), and crash-recovery teleports snap rather than sliding across the map.
5. Quick sanity: tutorial + challenge modes still enter/exit (transition entry-point change).

---

# PHASE 3 — DOCS

### Task 12: Bring the docs back to reality

**Files:**
- Modify: `planning_docs/Architecture.md`
- Modify: `CLAUDE.md`
- Modify: `planning_docs/ComboAndBoost.md`
- Modify: `planning_docs/code-review-20260430.md`
- **Do NOT touch `planning_docs/TODO.md`.**

Rules: tunables by name + behavior only, never values. Keep each doc's existing voice/structure; surgical edits.

> Phase 1's doc reality (Noray removal, NPC managers, `entities/`, Terrain3D collision, live results, breadcrumbs, `is_rev_limited` sync) was already written into CLAUDE.md / Architecture.md / code-review triage on 2026-08-01. This task documents ONLY what Phase 2 changes.

- [ ] **Step 1: CLAUDE.md** — Add `BoostController` to the PlayerEntity controller list.
- [ ] **Step 2: Architecture.md** —
  - Player Entity: controller table gains `BoostController`; Synced State section: boost vars now `%BoostController:*`, combo vars `%TrickController:*`.
  - Spawn Manager RPC list: add `request_respawn` + the sender-guard rule ("broadcast RPCs reject non-server senders; clients use request_respawn").
  - Gamemode Manager: late-join contract (`is_late_joinable`, `serialize_state_for_late_joiner`/`apply_state_from_host`, free-roam fallback, race-hijack guard); `change_gamemode` as the single transition entry point.
  - NPC section: note client-side transform smoothing (`sync_transform` lerp) replacing raw transform replication.
- [ ] **Step 3: ComboAndBoost.md** — rewrite "Where the logic lives" table: earn = TrickController, spend = BoostController, bank = TrickManager, UI/FX unchanged. Correct the framing: netfox forces rollback-tick *execution*; state *location* is the controller-ownership pattern. Move the `BOOST_*` tunables rows under BoostController.
- [ ] **Step 4: code-review-20260430.md** — extend the 2026-08-01 triage block: authority holes CLOSED (Task 8), late-join contract BUILT (Task 9), BoostController split DONE (Task 10); `BikeSkinDefinition` split + `user://` path leak still OPEN.
- [ ] **Step 5: Verify** — re-read each edited section against the actual code you just wrote. No values in docs.
- [ ] **Step 6: Commit point** — final commit ("docs: sync Architecture/CLAUDE/ComboAndBoost with code").

---

## Self-review notes (already applied)

- Human rows cached before `runner.stop()` (Task 5) because `stop()` clears `_player_states` — verified in sequential_task_runner.gd:63.
- `%TrickController` addressable: `unique_name_in_owner = true` confirmed at player_entity.tscn:1216.
- `Physics_Update` exists on base State (state.gd:19).
- `RACE_DNF` key becomes unused after Task 5 — leave it in the CSV (localization keys are cheap; removing strings is not this plan's job).
- Known deliberate duplication: Tasks 3/5 edit road_race + street_race twice each — do not attempt to merge the files.
