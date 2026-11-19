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
WIDGET_OUTPUT="$PWD/artifacts/LifeFlow-widget.ipa"
APP_STAGE="$STAGE/Payload/LifeFlow.app"
EXTENSION="$APP_STAGE/PlugIns/LifeFlowWidget.appex"
test -d "$EXTENSION"
python3 - "$APP_STAGE" "$EXTENSION" <<'PY'
import json
import pathlib
import sys

host, widget = map(pathlib.Path, sys.argv[1:])
intent = "CompleteWidgetTaskInAppIntent"

def actions(bundle):
    path = bundle / "Metadata.appintents" / "extract.actionsdata"
    return json.loads(path.read_text(encoding="utf-8"))["actions"] if path.is_file() else {}

host_action = actions(host)[intent]
widget_action = actions(widget)[intent]
assert host_action["fullyQualifiedTypeName"] == "LifeFlow." + intent
assert widget_action["fullyQualifiedTypeName"] == "LifeFlowWidget." + intent
assert host_action["identifier"] == widget_action["identifier"] == intent
assert host_action["openAppWhenRun"] is False and widget_action["openAppWhenRun"] is False
for bundle in (host, widget):
    assert set(actions(bundle)) == {intent}

print("Verified the completion action in both the app and widget")
PY

# AltStore discovers capabilities from the executable's signature. Ad-hoc
# signatures carry the requested entitlements without a development profile.
IDENTITY='-'
ENTITLEMENTS="$PWD/Configuration/Widget.entitlements"
/usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none --generate-entitlement-der --entitlements "$ENTITLEMENTS" "$EXTENSION"
/usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none --generate-entitlement-der --entitlements "$ENTITLEMENTS" "$APP_STAGE"
/usr/bin/codesign --verify --deep --strict "$APP_STAGE"
rm -f "$WIDGET_OUTPUT"
(cd "$STAGE" && /usr/bin/zip -qry "$WIDGET_OUTPUT" Payload)

# The regular package uses the original unsigned executable and no extension.
rm -rf "$APP_STAGE"
cp -R "$APP" "$APP_STAGE"
rm -rf "$APP_STAGE/PlugIns"
rm -f "$OUTPUT"
(cd "$STAGE" && /usr/bin/zip -qry "$OUTPUT" Payload)
echo "Created: $OUTPUT (without widget)"
echo "Created: $WIDGET_OUTPUT (ad-hoc signed, requires AltStore Classic re-signing)"
