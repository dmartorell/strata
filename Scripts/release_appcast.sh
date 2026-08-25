#!/usr/bin/env bash
set -euo pipefail

: "${APP_PATH:?}"
: "${SPARKLE_BIN:?}"
: "${SPARKLE_PRIVATE_ED_KEY:?}"
: "${DOWNLOAD_URL_PREFIX:?}"

output_dir="${OUTPUT_DIR:-$PWD/dist}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$output_dir" "$work_dir/archives"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
archive="$work_dir/archives/Siyahamba-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$archive"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_BIN/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --embed-release-notes \
  -o "$work_dir/appcast.xml" \
  "$work_dir/archives"
cp "$archive" "$output_dir/"
cp "$work_dir/appcast.xml" "$output_dir/appcast.xml"
