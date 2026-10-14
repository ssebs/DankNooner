# Debug

## VSCode integration

- Editor Settings > Text Editor > External
  - Exec Path: `/path/to/vscodium`
  - Exec Flags: `/path/to/DankNooner/DankNooner.code-workspace --goto {file}:{line}:{col}`
  - Use External Editor: ✅

### Note on running 2 windows side-by-side:

- Go to: Debug > Customize Run Instances
- Enable Multiple Instances: 2
- Launch Arguments:
  - > Enable both
  - `--position 5,0 --resolution 1280x800`
  - `--position 1290,0 --resolution 1280x800`
  - User args: (needs to be after `--`)
    - `--disable-audio` to disable audio
    - `--verbose` turns on every debug toggle in any build (`DebugUtils.verbose`): netfox warnings
      (hidden by default: `netfox_log_level` is Error), plus the inspector toggles checked through
      `DebugUtils.is_debug()` — `debug_verbose` (MovementController, EngineSoundEvent),
      `debug_netcode_metrics`, `debug_prof`. Per-tick prints: expect it to slow the game.
  - Each instance needs its own `--log-file <path>` or they overwrite each other's `godot.log`

### Reloading a saved scene

- Go to: Editor > Editor settings
- Shortcuts > Reload Saved Scene
- Set to ALT+R
