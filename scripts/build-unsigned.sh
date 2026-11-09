#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'XcodeGen is required: brew install xcodegen'; exit 1; }
swift test
bash scripts/prepare-icon.sh
xcodegen generate
xcodebuild -project LifeFlow.xcodeproj -scheme LifeFlow -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP='build/Build/Products/Release-iphoneos/LifeFlow.app'
test -d "$APP"
mkdir -p artifacts
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
OUTPUT="$PWD/artifacts/LifeFlow-unsigned.ipa"
if [ -e "$OUTPUT" ]; then rm "$OUTPUT"; fi
(cd "$STAGE" && /usr/bin/zip -qry "$OUTPUT" Payload)
echo "Created: $OUTPUT (unsigned; requires AltStore Classic signing)"

