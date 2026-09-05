#!/bin/bash
set -euo pipefail

# Build Fluxa Direct without launching it. Development bundles cannot be packaged for release.
FLUXA_REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$FLUXA_REPO_DIR"
VERIFY_OPTIONS=(--allow-local-signature)
case "${1:-}" in
    --development) VERIFY_OPTIONS+=(--allow-unconfigured-updater) ;;
    --help|-h)
        echo "Usage: ./build.sh [--development]"
        echo "Default builds require SUFeedURL and SUPublicEDKey. No key is generated."
        exit 0 ;;
    "") ;;
    *) echo "Usage: ./build.sh [--development]" >&2; exit 1 ;;
esac
if [[ "$#" -gt 1 ]]; then
    echo "Usage: ./build.sh [--development]" >&2
    exit 1
fi

BINARY_NAME="Fluxa"
# The certificate every published build is signed with. See the signing section below for why a
# stable identity is required rather than preferred.
RELEASE_SIGN_IDENTITY="Fluxa Code Signing"
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
RESOURCES_DIR="Sources/${BINARY_NAME}/Resources"
python3 packaging/verify-bundle.py "$RESOURCES_DIR/Info.plist" "${VERIFY_OPTIONS[@]}"

echo "🔨 Building Fluxa (release)..."
# SwiftPM does not track the plist passed to -sectcreate as a linker input. Force a relink
# so version/key/feed-only changes update the executable as well as the bundle's Info.plist.
rm -f "$BUILD_DIR/$BINARY_NAME"
mkdir -p .build
if ! swift build -c release --arch arm64 --force-resolved-versions -Xswiftc -warnings-as-errors \
    > .build/fluxa-release-build.log 2>&1; then
    cat .build/fluxa-release-build.log >&2
    exit 1
fi

echo "📦 Creating app bundle structure..."
SPARKLE_SOURCE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
codesign --verify --deep --strict "$SPARKLE_SOURCE"
FLUXA_STAGE="$(mktemp -d "$FLUXA_REPO_DIR/.build/fluxa-bundle.XXXXXX")"
trap 'rm -rf "$FLUXA_STAGE"' EXIT
BUNDLE_NAME="$FLUXA_STAGE/Fluxa.app"
mkdir -p "${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUNDLE_NAME}/Contents/Resources"
mkdir -p "${BUNDLE_NAME}/Contents/Frameworks"

echo "📋 Copying files..."
cp "${BUILD_DIR}/${BINARY_NAME}" "${BUNDLE_NAME}/Contents/MacOS/${BINARY_NAME}"
cp "${RESOURCES_DIR}/fluxa.icns" "${BUNDLE_NAME}/Contents/Resources/"
cp "${RESOURCES_DIR}/Info.plist" "${BUNDLE_NAME}/Contents/"
# The DMG references this signed resource so Finder's Show Hidden Files preference
# cannot expose a loose background file over the installer artwork.
cp "packaging/dmg-background.tiff" "${BUNDLE_NAME}/Contents/Resources/InstallerBackground.tiff"
# SwiftPM resource bundle — resolved at runtime via Bundle.fluxaResources
ditto "${BUILD_DIR}/${BINARY_NAME}_${BINARY_NAME}.bundle" "${BUNDLE_NAME}/Contents/Resources/${BINARY_NAME}_${BINARY_NAME}.bundle"
# Preserve the complete upstream framework, all helpers, symlinks and executable permissions.
ditto "$SPARKLE_SOURCE" "$BUNDLE_NAME/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$BUNDLE_NAME/Contents/Resources/Sparkle-LICENSE.txt"

# Remove Swift's development-only Xcode toolchain rpath from our executable before signing.
while IFS= read -r FLUXA_RPATH; do
    case "$FLUXA_RPATH" in
        /*.xctoolchain/*)
            install_name_tool -delete_rpath "$FLUXA_RPATH" "$BUNDLE_NAME/Contents/MacOS/Fluxa" ;;
    esac
done < <(otool -l "$BUNDLE_NAME/Contents/MacOS/Fluxa" | awk '
    /cmd LC_RPATH/ { getline; getline; sub(/^ *path /, ""); sub(/ \(offset.*$/, ""); print }
')

# A stable signing identity is the default when one is available, and ad-hoc only as a fallback.
#
# This is not cosmetic. An ad-hoc signature's designated requirement is the binary's own cdhash, so
# it changes on every build; macOS ties keychain ACLs and permission grants to that requirement and
# therefore stops recognising the app after every update, asking each user to authorise Fluxa again.
# A certificate-backed requirement pins to the certificate instead and survives every rebuild.
#
# Apple only issues Developer ID through the paid program, so releases use a locally generated
# self-signed code-signing certificate. Gatekeeper treats that exactly like ad-hoc — a downloaded
# build still needs the usual first-run approval — but the grants now persist across updates.
# Losing the certificate costs every user one final re-authorisation, so it is backed up outside
# this repository and never committed.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    if security find-identity -v -p codesigning | grep -q "$RELEASE_SIGN_IDENTITY"; then
        SIGN_IDENTITY="$RELEASE_SIGN_IDENTITY"
    else
        echo "⚠️  '$RELEASE_SIGN_IDENTITY' not found in the keychain — falling back to ad-hoc." >&2
        echo "    Ad-hoc builds re-prompt every user for permissions after each update." >&2
        SIGN_IDENTITY="-"
    fi
fi
SPARKLE_FRAMEWORK="$BUNDLE_NAME/Contents/Frameworks/Sparkle.framework"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    # Explicit certificate builds follow Sparkle's documented inside-out signing order.
    # Do not use --deep signing or apply Fluxa's entitlements to the helper binaries.
    SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --preserve-metadata=entitlements \
        "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime "$SPARKLE_VERSION/Autoupdate"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime "$SPARKLE_VERSION/Updater.app"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime "$SPARKLE_FRAMEWORK"
else
    # Ad-hoc Direct builds preserve all vendor signatures. No stripping or re-signing.
    VERIFY_OPTIONS+=(--vendor-source "$FLUXA_REPO_DIR/$SPARKLE_SOURCE")
fi
echo "🔐 Signing app bundle (identity: ${SIGN_IDENTITY})..."
SIGN_OPTIONS=(
    --force
    --sign "${SIGN_IDENTITY}"
    --entitlements Fluxa.entitlements
)

# Opt-in local-development fallback: a normal ad-hoc signature derives its designated requirement
# from the binary hash, which changes on every rebuild and makes macOS ask for Accessibility again.
# The identifier-only requirement is intentionally never the default because it is weaker than a
# certificate-backed identity and must not be distributed in a public release artifact.
if [[ "${SIGN_IDENTITY}" == "-" && "${FLUXA_STABLE_LOCAL_REQUIREMENT:-0}" == "1" ]]; then
    SIGN_OPTIONS+=(
        --identifier "com.giuseppe.fluxa"
        --requirements '=designated => identifier "com.giuseppe.fluxa"'
    )
fi

codesign "${SIGN_OPTIONS[@]}" "${BUNDLE_NAME}"
python3 packaging/verify-bundle.py "$BUNDLE_NAME" "${VERIFY_OPTIONS[@]}"

# Replace only generated repo output after validation; never touch the installed app.
rm -rf "$FLUXA_REPO_DIR/Fluxa.app"
mv "$BUNDLE_NAME" "$FLUXA_REPO_DIR/Fluxa.app"
echo "Created: $FLUXA_REPO_DIR/Fluxa.app"
echo "No installation, launch, key generation or publication was performed."
