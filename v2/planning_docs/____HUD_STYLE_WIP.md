# HUD Style Pass — design (WIP)

> Designed 2026-10-27 in a brainstorm with mockups (final: `.superpowers/brainstorm/392-1793143843/content/hud-fade-v18.html`,
> not committed). Delete this file once it ships and its rules are folded into
> [Architecture](./Architecture.md) and [ComboAndBoost](./ComboAndBoost.md).

- [Why](#why)
- [Goals / non-goals / anti-goals](#goals--non-goals--anti-goals)
- [Spec (decided)](#spec-decided)
- [What exists today](#what-exists-today)
- [Phases](#phases)
- [Open questions](#open-questions)
- [Left to the builder](#left-to-the-builder)

## Why

The riding HUD is inconsistent: some text sits on bordered glass panels, some on translucent black
strips, some on nothing, with ad-hoc spacing, about five text treatments (glow tube, thin outline,
12px black outline, BBCode outlines), seven-plus font sizes, and colors that mean several things at
once. Every widget also animates in its own way, so the juice reads as noise.

The game has to fit the existing logo, which is all over the socials: flat white MuseoModerno
SemiBold with one flat blue accent (the bike), no outline, no glow. The world already carries the
neon; the HUD should carry the brand. Principles: *Practical UI* (few sizes, one meaning per
color, consistent spacing, grouping by proximity).

## Goals / non-goals / anti-goals

- **Goal:** one small rule set that every riding-HUD element follows, plus one shared motion vocabulary.
- **Goal:** readable over the worst backgrounds (the gas station: bright grid, glowing edges, white walls).
- **Non-goal (this pass):** menus, and the other HUD states (results, gamemode event, fuel-up). They
  adopt the rules later.
- **Anti-goal:** new panels, new glow text, or per-widget special-case styling. If something needs
  an exception, the rule is wrong; come back and change the rule.

## Spec (decided)

### Type

- **Two styles.** *Title* (SemiBold) for values and hero moments: speed, callouts, combo, scores,
  names. *Main* (Medium) for words: labels, hints, trick names, feed text, descriptions.
- **Sizes:** 16 · 20 · 28 · 36 · 48 · 80. 16 is dim labels/headers, 20 body, 28 secondary values,
  36 instruction + callouts, 48 combo, 80 speed.
- **Contrast:** every HUD text gets the same dark outline (`UI_GLASS`, a little thicker at 48/80) plus
  a hard drop shadow under it. The outline is dark, never glowing, so white can't blend into neon edges.
- **No panels behind text.** Readability comes from the outline + one soft dark scrim in each HUD corner.

### Objects

Key caps (`InputPrompt`), the minimap frame, bars (RPM, boost segments, respawn, XP) and the
compass arrow are "objects" and share one style: blue stroke, the house slanted corners, dark fill,
blue neon halo. Nothing else gets a stroke.

### Color (one meaning each)

| Color | Means |
|---|---|
| white / dim white | default text / labels, secondary |
| `UI_BLUE` | **you**: your name, your leaderboard row, your progress |
| `UI_GOLD` | reward: callouts, combo, XP, wheelie balance point |
| `UI_RED` | danger: bails, warnings, over-rotation |
| `UI_GREEN` | money only |

Your own name is blue in the feed and leaderboard (reverts the green `NameTagLabel`/`OWN_NAME_COLOR`
change made 2026-10-27).

### Spacing

8 inside a group, 24 between related groups, 48 between unrelated sections and to the screen edge.
Every group hangs off a corner or the screen's horizontal middle line; right-side groups right-align.

### Layout

| Where | What |
|---|---|
| Top-left | Event title + step (`2 / 5`) + description |
| Top-centre | Instruction ("Drive to the start") at 36 |
| Top-right | Money + level, then the **full** leaderboard (`top_count` 0, no "…" row) |
| Mid-left, above middle line | Pinned tricks, under a dim "Pinned" label. **Only exists if something is pinned.** |
| Mid-left, below middle line | Trick feed, newest on top, growing down toward the map, capped short of it. 48 gap to pinned. |
| Bottom-left | Minimap, then a hint column: `T Tricks` above `M Map` / `R Respawn` / `Use Item` |
| Bottom-right | Centred stack: compass arrow + distance → speed + unit + gear → RPM bar; boost column + boost key to its right |
| Bottom-centre | Warnings (Wrong way!, missed checkpoint), red, shaking |
| Centre | Hero moments only: trick callouts + score pops, the wheelie meter, countdown, respawn bar |

- **Hold T:** the T key fills blue, the current state shows beside it, and the `M / R / Use Item`
  hints swap in place for that state's trick bindings (today's contextual rows). Max 3 rows (the
  hints' height); extra tricks spill into new columns. Release swaps back.
- **Trick rows** (pinned and held) read like the hints: key cap with the input first, then the trick,
  then its state dim.
- **Feed lines:** no per-line panel; text only.

### Motion (shared verbs)

| Verb | Means | Used by |
|---|---|---|
| Pop | a value went up | leaderboard scores, money/XP, live combo score |
| Wheelie | a callout arrives: tilts back from bottom-left (the logo's lifting "o"), settles | trick callouts |
| Punch | a tier changed | combo ×N |
| Shake | danger only | warnings, wheelie over-rotation |
| Flash + slide | a new line | feed lines |

- **Callouts:** Title 36, gold, enter with *wheelie*, then **sink down** as they fade (today they drift
  up; score pops sink too). Bails stay red.
- **Compass arrow:** sized like today, white with the dark outline and blue halo, loops a short nudge
  along its heading.

### Wheelie meter

The logo bike under the live score, tilting about its rear wheel (today's behavior), with:
- **Color:** blue approaching → **gold** in the balance point → **red** past it. Drops today's ice and
  green steps (green is money).
- **Verb:** **throbs** (scale pulse) in the balance point; **shakes** only past it. Today it shakes
  inside the balance point, which contradicts "shake = danger".
- **Balance arc:** a thin arc around the rear-wheel pivot from level to vertical, hairline at the
  ends and fattest across the balance window. Approach dim white, window gold, past red. A dot rides
  the arc at the current pitch. Built from the same `window` (min, low, high, max) that
  `show_pitch_icon()` already receives, so it's right per bike; mirrored for stoppies.

## What exists today

- **Theme:** `scripts/gen_neon_theme.py` generates `DankNoonerNeon.tres` and `hud_neon.tres` from
  `DankNooner.tres` / `hud.tres` and the `UI_*` palette in `utils/constants.gd`. The default font
  (`resources/fonts/museo_moderno_emoji.tres`) is already SemiBold; Bold is used for headings and the
  feed's names/points. No Medium variation exists. Scanlines were removed 2026-10-27.
- **Variations in play on the riding HUD:** `HUDPanel` (event panel, leaderboard panel), `FeedPanel`
  (per feed line), `GlowLabel` / `PopupLabel` (white in a blue tube), `XPLabel`, `WarningLabel`,
  `MoneyLabel`, `NameTagLabel` (own leaderboard name).
- **Flashes:** `HUDFlash` tints a panel's `self_modulate`. Used by `riding_hud_state.gd` (leaderboard
  and event panels) and `TrickFeed` (each line's panel). With panels gone, it needs a new target.
- **Bespoke motion constants:** `ComboCounter` (scale per tier, punch, trauma shake), `TrickPopups`
  (pop scale, drift, tilt, fade, callout stacking, wheelie icon smoothing/shake), `RaceLeaderboard`
  (cell pop, own-row punch, reorder slide), `TrickFeed` (fade in/hold/out, flash colors).
- **Compass:** `TargetCompass` draws its arrow in `_draw()` in `Minimap.COLOR_CHECKPOINT` with a black
  line, top-centre. While a guide target is on screen it **pins over the target** instead.
- **Trick prompt:** `TrickPrompt` (mid-left) = `T` header + contextual rows while the trick button is
  held (`_show_trick_prompt`) + always-on pinned rows (`_rebuild_trick_rows`, from
  `save_manager.current_save["pinned_tricks"]`). Rows are `TrickRow` (`menus/tricks_menu/components/`).
- **Suggested event tricks:** `HUD_EventTricks`, a separate label under the leaderboard.
- **Crash message:** `HUD_GAME_MSG` top-left ("CRASHED - Respawning..."); respawn bar is centred.
- **Leaderboard:** riding HUD sets `top_count` 3.

## Phases

Each phase: lint + headless parse check, then the user playtests before the next.

1. **Theme + type + color.** In `gen_neon_theme.py` / the base themes: Title and Main styles (add a
   Medium variation), the shared outline + hard drop on all HUD text, the object style for key caps
   and bars. Replace `GlowLabel`/`PopupLabel` glow with flat text + color. Own name and row go blue.
2. **Layout.** Restructure `riding_hud_state.tscn` per the layout table: remove `HUDPanel` /
   `FeedPanel` from the riding HUD, add the corner scrims, full leaderboard, feed to mid-left,
   pinned tricks above it (hidden when empty), `T` into the bottom-left hint column with the hold
   swap, compass into the bottom-right stack, warnings to bottom-centre.
3. **Motion.** One shared static helper for the five verbs (grow `HUDFlash`, don't add a sibling),
   then migrate `ComboCounter`, `TrickPopups`, `RaceLeaderboard`, `TrickFeed`, `riding_hud_state.gd`
   off their bespoke constants. Callouts go gold/36/sink; arrow nudge.
4. **Wheelie meter.** Recolor + re-verb the pitch icon, then the balance arc.

## Open questions

Ask before the phase that needs them.

- **Phase 2:** when the guide target is on screen, `TargetCompass` pins over it. Keep that (the arrow
  leaves the bottom-right stack and flies into the world), or always stay in the stack?
- **Phase 2:** suggested event tricks: fold them into the trick list (tagged gold "event") or keep the
  separate label? Floated, not decided.
- **Phase 2:** move "CRASHED - Respawning..." next to the centred respawn bar? Floated, not decided.
- **Phase 2:** the mockups showed a gold XP bar under money + level in place of the "2,461 XP" text.
  Never discussed; keep the text unless the user says otherwise.
- **Phase 3:** combo is the only 48. Drop 48 from the scale (combo at 36 or 80)? Floated, not decided.

## Left to the builder

- Which font is the theme default (Medium for Main is the likely answer, with Title as a variation).
- Scrim implementation (a gradient texture or shader on one full-rect control under the HUD).
- Outline/shadow sizes and every motion timing, tuned in game against the gas station.
- New localization keys (e.g. the "Pinned" label).
- How the arc is drawn (`_draw()` polygon with per-vertex width is the likely route).
