#!/bin/bash
set -euo pipefail

# Create a Sparkle update ZIP from the same signed bundle used by package-dmg.sh.
# No key access, app execution, appcast mutation or publication occurs here.
FLUXA_REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$FLUXA_REPO_DIR"
if [[ "$#" != 2 || "$1" != "--output" || -z "$2" ]]; then
    echo "Usage: ./package-update.sh --output path/to/new/Fluxa.zip" >&2
    exit 1
fi
FLUXA_OUTPUT="$2"
if [[ "$FLUXA_OUTPUT" != /* ]]; then
    FLUXA_OUTPUT="$FLUXA_REPO_DIR/$FLUXA_OUTPUT"
fi
if [[ "$FLUXA_OUTPUT" != *.zip || ! -d "$(dirname "$FLUXA_OUTPUT")" || -e "$FLUXA_OUTPUT" || -L "$FLUXA_OUTPUT" ]]; then
    echo "Choose an unused .zip path with an existing parent directory. Nothing was overwritten." >&2
    exit 1
fi
python3 packaging/verify-bundle.py "$FLUXA_REPO_DIR/Fluxa.app"
FLUXA_STAGE="$(mktemp -d "$(dirname "$FLUXA_OUTPUT")/.fluxa-update.XXXXXX")"
echo "Temporary output (retained on failure): $FLUXA_STAGE"
ditto -c -k --sequesterRsrc --keepParent "$FLUXA_REPO_DIR/Fluxa.app" "$FLUXA_STAGE/Fluxa.zip"
ditto -x -k "$FLUXA_STAGE/Fluxa.zip" "$FLUXA_STAGE/extracted"
python3 packaging/verify-bundle.py "$FLUXA_STAGE/extracted/Fluxa.app"
python3 - "$FLUXA_REPO_DIR" "$FLUXA_STAGE/extracted" <<'PY'
from pathlib import Path
import runpy
import sys

repo, extracted = map(Path, sys.argv[1:])
checks = runpy.run_path(str(repo / "packaging/verify-bundle.py"))
checks["require"]({p.name for p in extracted.iterdir()} == {"Fluxa.app"}, "Unexpected update ZIP contents.")
checks["require"](checks["tree_manifest"](repo / "Fluxa.app") == checks["tree_manifest"](extracted / "Fluxa.app"),
                  "Update ZIP did not preserve the signed bundle, file modes or symlinks.")
PY
ln "$FLUXA_STAGE/Fluxa.zip" "$FLUXA_OUTPUT"
rm -rf "$FLUXA_STAGE"
shasum -a 256 "$FLUXA_OUTPUT"
echo "Created update archive: $FLUXA_OUTPUT"
echo "It still needs an Ed25519 signature/appcast before release. No key was accessed and nothing was published."
