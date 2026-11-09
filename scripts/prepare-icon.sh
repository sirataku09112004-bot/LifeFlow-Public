#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DIR='Sources/Assets.xcassets/AppIcon.appiconset'
mkdir -p "$DIR"
/usr/bin/sips -s format png -z 1024 1024 Design/IconSource.jpg --out "$DIR/AppIcon.png" >/dev/null

