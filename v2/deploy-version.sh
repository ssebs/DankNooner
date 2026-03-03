#!/bin/bash

PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

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

read -p "Push $NEW_TAG and update project.godot? [Y/n] " confirm
confirm=${confirm:-Y}

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sed -i "s/config\/version=\"[^\"]*\"/config\/version=\"$NEW_TAG\"/" ./project.godot

    git add ./project.godot
    git commit -m "$NEW_TAG release"
    git tag "$NEW_TAG"
    git push origin "$NEW_TAG"
    git push origin main
    echo "Deployed $NEW_TAG to https://github.com/ssebs/DankNooner/"
else
    echo "Aborted."
fi

read -p "Press enter to close"
