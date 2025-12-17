#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

project="apps/macos/OverlayScribe/OverlayScribe.xcodeproj"
scheme="OverlayScribe"
configuration="Debug"
derived_data_path="$root_dir/.derived-data"

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  build

app_path="$derived_data_path/Build/Products/$configuration/$scheme.app"
if [[ ! -d "$app_path" ]]; then
  echo "Expected app bundle at: $app_path" >&2
  exit 1
fi

echo "==> Launching: $app_path"
open -n "$app_path"
