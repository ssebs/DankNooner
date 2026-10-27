#!/bin/bash

PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

# Commit subjects that start unchecked in the changelog picker
JUNK_RE='^(todo|imgs?|wip|v[0-9]+\.[0-9]+\.[0-9]+ release)$'

draw_picker() {
    local i box ptr
    for i in "${!COMMITS[@]}"; do
        box="[ ]"; ((CHECKED[i])) && box="[x]"
        ptr=" "; ((i == CURSOR)) && ptr=">"
        printf "\033[K%s %s %s\n" "$ptr" "$box" "${COMMITS[i]:0:$((COLS - 7))}"
    done
}

# Arrows move, space toggles, enter confirms. Result is in CHECKED.
pick_commits() {
    local key n=${#COMMITS[@]}
    CURSOR=0
    COLS=$(tput cols 2>/dev/null || echo 100)
    echo "Changelog (up/down move, space toggle, enter done):"
    printf "\033[?25l"
    while true; do
        draw_picker
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 key
                [[ "$key" == "[A" ]] && ((CURSOR > 0)) && CURSOR=$((CURSOR - 1))
                [[ "$key" == "[B" ]] && ((CURSOR < n - 1)) && CURSOR=$((CURSOR + 1))
                ;;
            " ") CHECKED[CURSOR]=$((1 - CHECKED[CURSOR])) ;;
            "") break ;;
        esac
        printf "\033[%dA" "$n"
    done
    printf "\033[?25h"
}

# Prepends this version's section under the "# Changelog" header
write_changelog() {
    local i section="## $NEW_TAG - $(date +%F)"$'\n\n'
    for i in "${!COMMITS[@]}"; do
        ((CHECKED[i])) && section+="- ${COMMITS[i]}"$'\n'
    done
    [ -f ./CHANGELOG.md ] || echo "# Changelog" > ./CHANGELOG.md
    { head -n 1 ./CHANGELOG.md; echo; printf "%s" "$section"; tail -n +2 ./CHANGELOG.md; } > ./CHANGELOG.md.tmp
    mv ./CHANGELOG.md.tmp ./CHANGELOG.md
}

trap 'printf "\033[?25h"' EXIT

echo "Current tag: $PREV_TAG"
read -p "Auto increment patch? [Y/n] " choice
choice=${choice:-Y}

if [[ "$choice" =~ ^[Yy]$ ]]; then
    # Parse version (assumes vX.Y.Z format)
    VERSION=${PREV_TAG#v}
    IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
    PATCH=$((PATCH + 1))
    NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
else
    read -p "Enter new tag: " NEW_TAG
fi

echo ""
echo "New tag: $NEW_TAG"
echo ""

mapfile -t COMMITS < <(git log "$PREV_TAG"..HEAD --no-merges --format=%s)
CHECKED=()
for c in "${COMMITS[@]}"; do
    if [[ "${c,,}" =~ $JUNK_RE ]]; then CHECKED+=(0); else CHECKED+=(1); fi
done
((${#COMMITS[@]})) && pick_commits

echo ""
read -p "Push $NEW_TAG, update project.godot and CHANGELOG.md? [Y/n] " confirm
confirm=${confirm:-Y}

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sed -i.bak "s/config\/version=\"[^\"]*\"/config\/version=\"$NEW_TAG\"/" ./project.godot && rm ./project.godot.bak
    write_changelog

    read -p "Edit CHANGELOG.md wording first? [Y/n] " edit
    edit=${edit:-Y}
    [[ "$edit" =~ ^[Yy]$ ]] && eval "$(git var GIT_EDITOR) ./CHANGELOG.md"

    git add ./project.godot ./CHANGELOG.md
    git commit -m "$NEW_TAG release"
    git tag "$NEW_TAG"
    git push origin "$NEW_TAG"
    git push origin main
    echo "Deployed $NEW_TAG to https://github.com/ssebs/DankNooner/"
else
    echo "Aborted."
fi

read -p "Press enter to close"
