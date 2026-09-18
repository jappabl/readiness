#!/bin/bash
# Fetches the Rive runtime. Run once after cloning.
#
# The framework is vendored rather than pulled through Swift Package Manager because
# SPM's downloader stalls indefinitely on Rive's binary artifact in some networks: the
# same URL fetches fine with curl, but the build hangs at zero CPU inside
# BinaryArtifactsManager.download with nothing written to the artifacts directory.
# Vendoring also drops a 477MB source checkout that exists only to point at this zip.
#
# It is not committed: 86MB of binary does not belong in git history.
set -euo pipefail

VERSION="6.27.0"
CHECKSUM="8f78adedd96e48a17a41ac25610847143d52f0bf1bc15bd916bd03b10ba3070d"
URL="https://github.com/rive-app/rive-ios/releases/download/${VERSION}/RiveRuntime.xcframework.zip"

cd "$(dirname "$0")/.."

if [ -d "Frameworks/RiveRuntime.xcframework" ]; then
    echo "RiveRuntime.xcframework already present. Delete it to re-fetch."
    exit 0
fi

echo "Fetching RiveRuntime ${VERSION}…"
mkdir -p Frameworks
curl -fsSL --max-time 900 -o /tmp/RiveRuntime.xcframework.zip "$URL"

# The same checksum Rive publishes in their Package.swift, so a vendored copy is
# provably the same binary SPM would have installed.
ACTUAL=$(shasum -a 256 /tmp/RiveRuntime.xcframework.zip | awk '{print $1}')
if [ "$ACTUAL" != "$CHECKSUM" ]; then
    echo "Checksum mismatch." >&2
    echo "  expected $CHECKSUM" >&2
    echo "  got      $ACTUAL" >&2
    rm -f /tmp/RiveRuntime.xcframework.zip
    exit 1
fi

unzip -q /tmp/RiveRuntime.xcframework.zip -d Frameworks/
rm -f /tmp/RiveRuntime.xcframework.zip

# Only the two iOS slices ship. The full archive carries tvOS, visionOS, macOS and
# Catalyst as well, which is 381MB for a phone app.
cd Frameworks/RiveRuntime.xcframework
rm -rf tvos-* xros-* macos-* ios-arm64_x86_64-maccatalyst
python3 - <<'PY'
import plistlib
with open("Info.plist", "rb") as f:
    info = plistlib.load(f)
keep = {"ios-arm64", "ios-arm64_x86_64-simulator"}
info["AvailableLibraries"] = [l for l in info["AvailableLibraries"]
                              if l["LibraryIdentifier"] in keep]
with open("Info.plist", "wb") as f:
    plistlib.dump(info, f)
PY

echo "Done. $(du -sh . | cut -f1) in Frameworks/RiveRuntime.xcframework"
