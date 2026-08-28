#!/bin/bash
set -euo pipefail

# Run only when changing the SVG. The committed multi-resolution TIFF lets release
# packaging work without a renderer or access to the design fonts.
FLUXA_PACKAGING_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUXA_REPO_DIR="$(dirname "$FLUXA_PACKAGING_DIR")"
FLUXA_ASSET_BUILD="$FLUXA_REPO_DIR/.build/dmg-assets"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "Install librsvg (brew install librsvg) to render the installer artwork." >&2
    exit 1
fi

mkdir -p "$FLUXA_ASSET_BUILD"
for FLUXA_SCALE in 1 2; do
    FLUXA_SUFFIX=""
    if [[ "$FLUXA_SCALE" -eq 2 ]]; then
        FLUXA_SUFFIX="@2x"
    fi
    FLUXA_PNG="$FLUXA_ASSET_BUILD/background$FLUXA_SUFFIX.png"
    rsvg-convert \
        --width "$((800 * FLUXA_SCALE))" --height "$((600 * FLUXA_SCALE))" \
        --output "$FLUXA_PNG" "$FLUXA_PACKAGING_DIR/dmg-background.svg"
done

# The @2x basename is significant: tiffutil uses it to assign the Retina DPI.
/usr/bin/tiffutil -cathidpicheck \
    "$FLUXA_ASSET_BUILD/background.png" \
    "$FLUXA_ASSET_BUILD/background@2x.png" \
    -out "$FLUXA_PACKAGING_DIR/dmg-background.tiff"
echo "Rendered: $FLUXA_PACKAGING_DIR/dmg-background.tiff (800 × 600 points, 1× + 2×)"
