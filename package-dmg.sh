#!/bin/bash
set -euo pipefail

# Package an existing public bundle and a readable guide outside the app. This never builds,
# installs, changes Gatekeeper/TCC settings, or overwrites an existing release artifact.
FLUXA_REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$FLUXA_REPO_DIR"
FLUXA_BUNDLE="$FLUXA_REPO_DIR/Fluxa.app"
FLUXA_GUIDE="$FLUXA_REPO_DIR/docs/First Launch.txt"
FLUXA_BACKGROUND="$FLUXA_REPO_DIR/packaging/dmg-background.tiff"
FLUXA_DMG_PYTHON="${FLUXA_DMG_PYTHON:-$FLUXA_REPO_DIR/.build/dmg-tools-venv/bin/python3}"
FLUXA_CUSTOM_OUTPUT=""

case "${1:-}" in
    --output)
        if [[ "$#" -ne 2 || -z "$2" ]]; then
            echo "Usage: ./package-dmg.sh [--output path/to/new-installer.dmg]" >&2
            exit 1
        fi
        FLUXA_CUSTOM_OUTPUT="$2"
        ;;
    --help|-h)
        echo "Usage: ./package-dmg.sh [--output path/to/new-installer.dmg]"
        echo "Paths are relative to the repo. Default: Fluxa.dmg. Existing files are never overwritten."
        exit 0
        ;;
    "") ;;
    *)
        echo "Usage: ./package-dmg.sh [--output path/to/new-installer.dmg]" >&2
        exit 1
        ;;
esac

if [[ ! -d "$FLUXA_BUNDLE" || ! -f "$FLUXA_GUIDE" ]]; then
    echo "Build the public bundle with ./build.sh first; the first-launch guide is also required." >&2
    exit 1
fi

if [[ ! -f "$FLUXA_BACKGROUND" ]]; then
    echo "Missing installer artwork. Run ./packaging/render-background.sh first." >&2
    exit 1
fi
if ! cmp -s "$FLUXA_BACKGROUND" "$FLUXA_BUNDLE/Contents/Resources/InstallerBackground.tiff"; then
    echo "The bundle's installer artwork is missing or stale. Rebuild with ./build.sh first." >&2
    exit 1
fi
if [[ ! -x "$FLUXA_DMG_PYTHON" ]] || ! "$FLUXA_DMG_PYTHON" -c 'import dmgbuild' 2>/dev/null; then
    echo "Set up the isolated packaging tools once:" >&2
    echo "  python3 -m venv .build/dmg-tools-venv" >&2
    echo "  .build/dmg-tools-venv/bin/python3 -m pip install -r packaging/requirements.txt" >&2
    exit 1
fi

codesign --verify --deep --strict "$FLUXA_BUNDLE"
python3 packaging/verify-bundle.py "$FLUXA_BUNDLE"
# codesign prefixes a synthesized (normal ad-hoc) requirement with "# ".
FLUXA_REQUIREMENT="$(codesign -d -r- "$FLUXA_BUNDLE" 2>&1 | sed -nE 's/^(# )?designated => //p')"
if [[ -z "$FLUXA_REQUIREMENT" ]]; then
    echo "Could not read the bundle's designated signing requirement." >&2
    exit 1
fi
if [[ "$FLUXA_REQUIREMENT" == 'identifier "com.giuseppe.fluxa"' ]]; then
    echo "Refusing to distribute the local identifier-only signature. Rebuild without FLUXA_STABLE_LOCAL_REQUIREMENT." >&2
    exit 1
fi

FLUXA_ARCHS="$(lipo -archs "$FLUXA_BUNDLE/Contents/MacOS/Fluxa")"
if [[ "$FLUXA_ARCHS" != "arm64" ]]; then
    echo "Expected an arm64-only Fluxa bundle; got: $FLUXA_ARCHS" >&2
    exit 1
fi

FLUXA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FLUXA_BUNDLE/Contents/Info.plist")"
if [[ ! "$FLUXA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected an explicit x.y.z release version in Info.plist." >&2
    exit 1
fi
FLUXA_OUTPUT="${FLUXA_CUSTOM_OUTPUT:-$FLUXA_REPO_DIR/Fluxa.dmg}"
if [[ "$FLUXA_OUTPUT" != /* ]]; then
    FLUXA_OUTPUT="$FLUXA_REPO_DIR/$FLUXA_OUTPUT"
fi
if [[ "$FLUXA_OUTPUT" != *.dmg || ! -d "$(dirname "$FLUXA_OUTPUT")" ]]; then
    echo "Choose a .dmg output path inside an existing directory." >&2
    exit 1
fi
if [[ -e "$FLUXA_OUTPUT" || -L "$FLUXA_OUTPUT" ]]; then
    echo "Already exists: $FLUXA_OUTPUT. Archive it or choose a new --output path; no file was overwritten." >&2
    exit 1
fi

# Build privately in the output directory, then use a non-overwriting hard link to
# publish the verified artifact. dmgbuild's internal -ov never touches a release.
FLUXA_STAGE="$(mktemp -d "$(dirname "$FLUXA_OUTPUT")/.fluxa-dmg.XXXXXX")"
FLUXA_STAGE_DMG="$FLUXA_STAGE/Fluxa.dmg"
echo "Packaging Fluxa $FLUXA_VERSION with the branded Retina installer..."
echo "Temporary output (retained on failure): $FLUXA_STAGE"
"$FLUXA_DMG_PYTHON" "$FLUXA_REPO_DIR/packaging/build-dmg.py" \
    --repo "$FLUXA_REPO_DIR" --output "$FLUXA_STAGE_DMG"
hdiutil verify "$FLUXA_STAGE_DMG"
ln "$FLUXA_STAGE_DMG" "$FLUXA_OUTPUT"
rm "$FLUXA_STAGE_DMG"
rmdir "$FLUXA_STAGE"
shasum -a 256 "$FLUXA_OUTPUT"
echo "Created: $FLUXA_OUTPUT"
