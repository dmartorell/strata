#!/usr/bin/env bash
set -euo pipefail

: "${APP_PATH:?}"
: "${SPARKLE_BIN:?}"
: "${SPARKLE_PRIVATE_ED_KEY:?}"
: "${DOWNLOAD_URL_PREFIX:?}"

previous_archive="${PREVIOUS_ARCHIVE:-}"
if [[ -n "$previous_archive" && ! -f "$previous_archive" ]]; then
  echo "No se encontró el ZIP de la release anterior: $previous_archive" >&2
  exit 1
fi

output_dir="${OUTPUT_DIR:-$PWD/dist}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$output_dir" "$work_dir/archives"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
archive="$work_dir/archives/Siyahamba-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$archive"
if [[ -n "$previous_archive" ]]; then
  cp "$previous_archive" "$work_dir/archives/"
fi

printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_BIN/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --maximum-versions 1 \
  --embed-release-notes \
  -o "$work_dir/appcast.xml" \
  "$work_dir/archives"
cp "$archive" "$output_dir/"
find "$work_dir/archives" -maxdepth 1 -type f -name '*.delta' -exec cp {} "$output_dir/" \;
cp "$work_dir/appcast.xml" "$output_dir/appcast.xml"
