#!/bin/bash
# Exports Steam builds with the demo/full app ID, then restores project.godot.
# Demo builds go to dist/demo/<os>/ instead of dist/<os>/.
# Usage: ./export.sh [demo|full|both] [preset ...]   (target defaults to both, presets to Windows, Linux, Mac)
set -eo pipefail
cd "$(dirname "$0")"

TARGET=${1:-both}
case "$TARGET" in
    demo | full | both) ;;
    *) echo "Unknown target '$TARGET'"; exit 1 ;;
esac
shift || true

PRESETS=("$@")
[ ${#PRESETS[@]} -eq 0 ] && PRESETS=("DankNoonerWindows" "DankNoonerLinux" "DankNoonerMac")

GODOT=$(sed -n 's/.*"godotTools.editorPath.godot4": *"\([^"]*\)".*/\1/p' .vscode/settings.json | tr -s '\\\\' '/')

set_app_id() {
    sed -i "s/^initialization\/app_data\/app_id=.*/initialization\/app_data\/app_id=$1/" ./project.godot
}

preset_export_path() {
    awk -v name="name=\"$1\"" '$0 == name {found = 1} found && /^export_path=/ {gsub(/^export_path=|"/, ""); print; exit}' ./export_presets.cfg
}

# Presets export in parallel; demo/full stay sequential since app_id lives in project.godot.
export_build() {
    local build=$1 app_id=$2 pids=()
    set_app_id "$app_id"
    for preset in "${PRESETS[@]}"; do
        local path
        path=$(preset_export_path "$preset")
        [ "$build" = demo ] && path=${path/#dist\//dist/demo/}
        echo "Exporting $preset ($build, app_id=$app_id) -> $path"
        "$GODOT" --headless --path . --export-release "$preset" "$path" 2>&1 | sed "s/^/[$preset $build] /" &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
}

ORIG_APP_ID=$(sed -n 's/^initialization\/app_data\/app_id=//p' ./project.godot)
trap 'set_app_id "$ORIG_APP_ID"; echo "Restored app_id=$ORIG_APP_ID"' EXIT

# Import once up front so the parallel exports don't race on the .godot/ cache.
"$GODOT" --headless --path . --import

if [ "$TARGET" != full ]; then export_build demo 5431410; fi
if [ "$TARGET" != demo ]; then export_build full 5416370; fi

echo ""
echo "Done: $TARGET build(s) in dist/"
read -p "Press enter to close"
