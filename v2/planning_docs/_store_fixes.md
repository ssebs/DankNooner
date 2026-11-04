# Dank Nooner store fixes

Everything from the store page and capsule art review, grouped by where you'll do the work. Items marked **(high impact)** move the needle most.



set better min specs for Steam

add gifs / imgs on steam description

explain PVP vs PVE vs Solo gameplay in steam description


“Even fueling up can be a challenge!” is your weakest bullet. Either make it specific (what makes it hard?) or cut it.




## Logo

Layer styles only, so the logo stays the same everywhere you already use it.

- [ ] **Add a neon-blue ring to both o's** (high impact) — Use the bike's wheel-rim blue, placed between the white fill and the existing black outline (blue inner stroke + black outer stroke). The blue makes them read as wheels; the black keeps them visible on dark backgrounds.
- [ ] **Optional: faint blue Outer Glow on the o's only** — Ties them to the neon in the art. Keep it subtle so it doesn't smear at small sizes.
- [ ] **Scale the lifted o up 10–20%** — So it reads as a wheel rather than a degree sign.
- [ ] **Make a small-size logo variant** — Same design with the gap before "ner" tightened a little. Use only below about 300 px wide, including the small capsule.

## Capsule renders in Godot

Build a capsule-only scene by duplicating your level, so you can cheat freely.

- [ ] **Clean up the set** — Hide or delete the grey placeholder boxes and anything that looks unfinished.
- [ ] **Set a low camera with a narrow FOV** — Knee height or lower, slightly in front of the bike. FOV 30–40° so the bike looms and the background compresses.
- [ ] **Pose the wheelie** — Pause at the balance point (`get_tree().paused` or `Engine.time_scale = 0`), tweak bones in the editor if needed. Keep the drink up.
- [ ] **Frame it tight** — Bike and rider fill about 60% of the frame, both wheels fully inside.
- [ ] **Turn on Glow, switch tonemapper, raise exposure** (high impact) — WorldEnvironment: Glow on so the neon blooms, AgX or ACES tonemap, exposure up a bit.
- [ ] **Add a warm orange accent** (high impact) — An orange Omni/SpotLight as a streetlight or headlight rimming the rider, or an orange/yellow rider outfit. This is what stops the art blending into Steam's navy UI.
- [ ] **Add tire smoke or sparks** — GPUParticles3D under the rear wheel.
- [ ] **Optional: second rider crashing in the background** — Pause on a good ragdoll frame. Sells the multiplayer chaos.
- [ ] **Add the screenshot script and render big** — F12 saves the viewport to `user://`. Launch with `godot --resolution 3840x2160`.
- [ ] **Render three passes** — Full scene; bike + rider alone on transparent (Environment background = Clear Color, viewport `transparent_bg` on); background alone with the rider hidden.

```gdscript
# Attach to any node in the capsule scene. Run with: godot --resolution 3840x2160
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://capsule_%d.png" % Time.get_ticks_msec())
```

## Finishing in Photoshop

No generative tools anywhere in this pipeline.

- [ ] **Set up one master PSD** — Renders as Smart Objects, one artboard per size: main 1232×706, header 920×430, small 462×174, vertical 748×896. Swapping a render or the logo updates all of them.
- [ ] **Recompose main and header capsules** (high impact) — Logo top-left, rider on the right, logo clear of the raised arm and drink. Soft dark glow or drop shadow behind the logo.
- [ ] **Motion blur the background layer only** — Rider stays sharp, the world streaks past.
- [ ] **Fix the color** — Curves to lift the crushed midtones; warm gradient on a Soft Light layer where the orange light hits; paint rim light on a Linear Dodge layer.
- [ ] **Add a light vignette** — Pulls focus to the bike.
- [ ] **Small capsule: add a tiny wheelie bike** — Crop it from your transparent render and place it in the gap on the right.
- [ ] **Vertical capsule: keep it, add the warm accent** — It's your strongest one. Also bring the rear wheel fully into frame.
- [ ] **Library hero: optional cleanup** — The mirrored clouds look a bit symmetrical. Low priority.
- [ ] **Stay clear of AI tools** — Skip Generative Fill/Expand, Neural Filters, and the Remove tool with generative AI on. Clone Stamp, Healing Brush and Content-Aware Fill are fine.

## Store page copy

Edits to the short description and About This Game.

- [ ] **Put "free to play" up front** (high impact) — In the short description or the first header. Right now it's only in tags and genre.
- [ ] **Say how monetization works** — One line: is everything earnable in-game, are purchases cosmetic only?
- [ ] **Add a GIF under each About section header** (high impact) — Wheelie through traffic, ragdoll crash, death wobbles, a stunt-race bat or shotgun hit.
- [ ] **Clarify public servers vs friends only** — Solo players need to know whether free roam has other riders without a group.
- [ ] **Match the co-op and PvE tags to the content** — Add a line about co-op/PvE content, or remove the Online Co-op and PvE tags.
- [ ] **Fix the fueling bullet** — Make "Even fueling up can be a challenge!" specific, or cut it.
- [ ] **Give a release window** — Even "2027" or "Early Access Q1" beats a bare "Coming soon".

## Steamworks settings and specs

Fields outside the description.

- [ ] **Tick controller support** (high impact) — Full or partial, if the game supports it. Many players filter on it.
- [ ] **Check Steam Deck compatibility** — You already list SteamOS.
- [ ] **Allow Windows 10** — List Windows 10/11 unless 10 truly doesn't run it.
- [ ] **Name real CPUs** — Replace "4 Core" with something like "Intel i5-6500 / Ryzen 3 1200".
- [ ] **Make GPU requirements consistent** — Windows minimum is a GTX 970 but Linux minimum is integrated. Recommended RTX 5060 looks high for a 2 GB stylized game; something like a GTX 1060 or RTX 2060 is likely closer.
- [ ] **Rewrite the Linux OS line** — "Ubuntu 22.04+ or equivalent / SteamOS" instead of Fedora version numbers.
- [ ] **Confirm you need the third-party EULA** — It's a small bit of friction at install.

## Check before you ship

- [ ] **Test every capsule at display size on Steam's background** — Small capsule at 231×87, header and main around 300 px wide, on `#1b2838`. Make sure the blue rings still read.
- [ ] **Show the small capsule to someone new** — Ask what the logo says. If they say "No ner," tighten the small variant more.
- [ ] **Push the new assets to the repo** — Then ask Claude to re-run the thumbnail test.