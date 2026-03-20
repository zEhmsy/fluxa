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

echo "🔐 Signing app bundle..."
codesign --force --sign - --entitlements Fluxa.entitlements "${BUNDLE_NAME}"

echo "✅ Done! Bundle created: ${BUNDLE_NAME}"
echo ""
echo "To install, run:"
echo "  cp -r ${BUNDLE_NAME} /Applications/"
echo ""
echo "To launch:"
echo "  open ${BUNDLE_NAME}"
