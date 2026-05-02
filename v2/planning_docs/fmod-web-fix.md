# FMOD Web Export — Build & Wire-Up

Tracking notes for getting FMOD working on the web (HTML5) export. Linked from
`addons/fmod_web_export/fmod_web_export_plugin.gd` (TODO at top of file) and
upstream PR https://github.com/utopia-rise/fmod-gdextension/pull/210.

## What's missing today

- `addons/fmod/libs/` has no `web/` folder — only desktop + mobile binaries.
- `addons/fmod/fmod.gdextension` has no `web.*.wasm32` library entry, so Godot
  loads nothing for FMOD when running in a browser.
- `web/custom_shell.html` preloads bank files into the Emscripten VFS but does
  not load FMOD's JS bridge (`fmodstudio.js`).
- `export_presets.cfg` preset.2: `html/custom_html_shell=""` — custom shell is
  not enabled for the web preset.
- DLLs in the desktop addon are Windows-only and cannot be loaded by a browser.

## Constraint: GitHub Pages

Deploy target is GitHub Pages, which does **not** allow setting COOP/COEP
headers. That means no `SharedArrayBuffer`, so:

- `variant/thread_support=false` must stay false.
- Need the **single-threaded** FMOD HTML5 build (the SConstruct already forces
  `threads=no` for godot-cpp on the `web` platform).
- `variant/extensions_support=true` is required (and already on).

## Versions to pin

These match upstream CI on the `web-support` branch — newer versions break the
build.

- FMOD HTML5 SDK: **2.03.11** (`fmodstudioapi20311html5.zip`)
- Emscripten: **3.1.56**
- SCons: **4.7.0**
- gdextension branch: `utopia-rise/fmod-gdextension` @ `web-support`

## Build steps (Linux)

Prereq: free FMOD developer account at fmod.com to download the HTML5 SDK.
There is no public mirror.

The SConstruct expects `fmod-gdextension/` and `libs/fmod/api/...` to be
**siblings** — same layout CI uses.

```bash
# 1. workspace
mkdir -p ~/fmod-build && cd ~/fmod-build

# 2. emscripten 3.1.56
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 3.1.56
./emsdk activate 3.1.56
source ./emsdk_env.sh   # must be sourced in every shell that runs scons
cd ..

# 3. clone PR branch with godot-cpp submodule
git clone --recurse-submodules -b web-support \
  https://github.com/utopia-rise/fmod-gdextension.git

# 4. drop FMOD HTML5 SDK in libs/fmod/
mkdir -p libs/fmod && cd libs/fmod
unzip /path/to/fmodstudioapi20311html5.zip
mv fmodstudioapi20311html5/api .
# expected: libs/fmod/api/studio/lib/w32/fmodstudio_wasm.a (and *L_wasm.a)
cd ../..

# 5. build
pip install --user scons==4.7.0 requests
cd fmod-gdextension
scons platform=web target=template_release -j$(nproc)
scons platform=web target=template_debug   -j$(nproc)
```

Outputs land in `fmod-gdextension/demo/addons/fmod/libs/web/`:

- `libGodotFmod.web.template_release.wasm32.wasm`
- `libGodotFmod.web.template_debug.wasm32.wasm`

## Project wiring (after binaries exist)

1. Copy both `.wasm` files into `v2/addons/fmod/libs/web/`.

2. Add web entries to `v2/addons/fmod/fmod.gdextension` under `[libraries]`:

   ```
   web.debug.wasm32   = "res://addons/fmod/libs/web/libGodotFmod.web.template_debug.wasm32.wasm"
   web.release.wasm32 = "res://addons/fmod/libs/web/libGodotFmod.web.template_release.wasm32.wasm"
   ```

3. Enable the custom shell in `v2/export_presets.cfg` preset.2:

   ```
   html/custom_html_shell="res://web/custom_shell.html"
   ```

4. Update `v2/web/custom_shell.html` to load `fmodstudio.js` before
   `engine.startGame()` (and ensure `fmodstudio.wasm` is reachable at the path
   the JS bridge expects). Bank preloading is already handled.

5. The `fmod_web_export` plugin already copies `.bank` files. It will also
   need to copy `fmodstudio.js`/`.wasm` next to `index.html` (or commit them
   under `v2/web/` so they end up in the export dir).

## CI consideration

Two options for `.github/workflows/build.yml`:

- **Commit the `.wasm` files under** `v2/addons/fmod/libs/web/` (LFS is on).
  Adds ~2.5 MB to the repo. Simplest.
- **Build them in CI** — mirror the upstream PR's job (FMOD secrets + emsdk +
  scons step before `firebelley/godot-export`). Cleaner, more setup.

Recommend committing the binaries first to get end-to-end working, then
automate later.

## Known issues to expect

From PR #210's own todo list and recent comments:

- `Module.FMOD_JS_MixerFastpathFunction is not a function` when playing
  sounds — open issue in the PR. May be fixed on
  `sphynx-owner/fmod-gdextension` branch `godot-module-restructure`
  (RafaelVidaurre's comment on issue #50 reports HTML5 working there).
- Firefox crashes the tab — known browser wasm bug. Test in Chromium.
- `AudioContext is not a constructor` (granitrocky's comment on issue #50)
  — downstream init issue, likely needs FMOD JS init to wait for a user
  gesture. Cross that bridge after the binary is in.
