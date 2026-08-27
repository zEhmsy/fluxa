#!/bin/bash
set -e

# Build script for Fluxa — creates a signed .app bundle with icon

BINARY_NAME="Fluxa"
BUNDLE_NAME="${BINARY_NAME}.app"
BUILD_DIR=".build/release"
RESOURCES_DIR="Sources/${BINARY_NAME}/Resources"

echo "🔨 Building Fluxa (release)..."
swift build -c release -Xswiftc -warnings-as-errors > /dev/null 2>&1

echo "📦 Creating app bundle structure..."
rm -rf "${BUNDLE_NAME}"
mkdir -p "${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUNDLE_NAME}/Contents/Resources"

echo "📋 Copying files..."
cp "${BUILD_DIR}/${BINARY_NAME}" "${BUNDLE_NAME}/Contents/MacOS/${BINARY_NAME}"
cp "${RESOURCES_DIR}/fluxa.icns" "${BUNDLE_NAME}/Contents/Resources/"
cp "${RESOURCES_DIR}/Info.plist" "${BUNDLE_NAME}/Contents/"
# SwiftPM resource bundle — resolved at runtime via Bundle.fluxaResources
cp -R "${BUILD_DIR}/${BINARY_NAME}_${BINARY_NAME}.bundle" "${BUNDLE_NAME}/Contents/Resources/"

# Ad-hoc by default. Set CODESIGN_IDENTITY to a stable identity (e.g. an Apple Development
# certificate) so macOS keeps keychain and permission grants across rebuilds — it ties them to the
# signature, and an ad-hoc one changes on every build.
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
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

echo "✅ Done! Bundle created: ${BUNDLE_NAME}"
echo ""
echo "To install, run:"
echo "  cp -r ${BUNDLE_NAME} /Applications/"
echo ""
echo "To launch:"
echo "  open ${BUNDLE_NAME}"
