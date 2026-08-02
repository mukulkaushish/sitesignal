#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
screenshot_directory="$project_directory/docs/screenshots"
target="${1:-}"
android_device_id="${ANDROID_DEVICE_ID:-emulator-5554}"

mkdir -p "$screenshot_directory"
cd "$project_directory"

capture_macos() {
  local theme="$1"
  local output="$screenshot_directory/macos-$theme.png"
  local capture_log
  local generated_output

  capture_log="$(mktemp)"

  flutter run \
    --device-id macos \
    --target test/screenshot_main.dart \
    --dart-define "SCREENSHOT_THEME=$theme" | tee "$capture_log"

  generated_output="$(sed -n 's/^SCREENSHOT_SAVED=//p' "$capture_log" | tail -n 1)"
  rm -f "$capture_log"
  test -n "$generated_output"
  cp "$generated_output" "$output"
  test -s "$output"
}

capture_android() {
  local theme="$1"
  local filename="sitesignal-android-$theme.png"
  local output="$screenshot_directory/android-$theme.png"

  flutter run \
    --device-id "$android_device_id" \
    --target test/screenshot_main.dart \
    --dart-define "SCREENSHOT_THEME=$theme"

  adb -s "$android_device_id" exec-out \
    run-as dev.sitesignal.app cat "cache/$filename" > "$output"
  test -s "$output"
}

case "$target" in
  macos)
    capture_macos light
    capture_macos dark
    ;;
  android)
    capture_android light
    capture_android dark
    ;;
  *)
    echo "Usage: $0 <macos|android>" >&2
    exit 64
    ;;
esac
