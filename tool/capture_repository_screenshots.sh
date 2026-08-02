#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
screenshot_directory="$project_directory/docs/screenshots"
target="${1:-}"
android_device_id="${ANDROID_DEVICE_ID:-emulator-5554}"

mkdir -p "$screenshot_directory"
cd "$project_directory"

enable_android_demo_mode() {
  adb -s "$android_device_id" shell settings put global sysui_demo_allowed 1
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command enter >/dev/null
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command clock -e hhmm 1200 >/dev/null
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command battery \
    -e level 100 -e plugged false >/dev/null
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command network \
    -e wifi show -e level 4 -e mobile show -e datatype lte >/dev/null
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command notifications \
    -e visible false >/dev/null
}

disable_android_demo_mode() {
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true
}

capture_macos() {
  local page="$1"
  local output="$screenshot_directory/macos-$page-light.png"
  local capture_log
  local generated_output

  capture_log="$(mktemp)"

  flutter run \
    --device-id macos \
    --target test/screenshot_main.dart \
    --dart-define "SCREENSHOT_PAGE=$page" | tee "$capture_log"

  generated_output="$(sed -n 's/^SCREENSHOT_SAVED=//p' "$capture_log" | tail -n 1)"
  rm -f "$capture_log"
  test -n "$generated_output"
  cp "$generated_output" "$output"
  test -s "$output"
}

capture_android() {
  local page="$1"
  local filename="sitesignal-android-$page-light.png"
  local output="$screenshot_directory/android-$page-light.png"
  local capture_log
  local flutter_pid
  local ready=false

  capture_log="$(mktemp)"
  enable_android_demo_mode
  adb -s "$android_device_id" shell \
    run-as dev.sitesignal.app rm -f "cache/$filename" >/dev/null 2>&1 || true
  flutter run \
    --device-id "$android_device_id" \
    --target test/screenshot_main.dart \
    --dart-define "SCREENSHOT_PAGE=$page" >"$capture_log" 2>&1 &
  flutter_pid=$!

  for _ in $(seq 1 180); do
    if adb -s "$android_device_id" shell \
      run-as dev.sitesignal.app test -s "cache/$filename" >/dev/null 2>&1; then
      ready=true
      break
    fi
    if ! kill -0 "$flutter_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if [[ "$ready" != true ]]; then
    cat "$capture_log" >&2
    kill -INT "$flutter_pid" >/dev/null 2>&1 || true
    wait "$flutter_pid" >/dev/null 2>&1 || true
    adb -s "$android_device_id" shell am force-stop dev.sitesignal.app || true
    disable_android_demo_mode
    rm -f "$capture_log"
    echo "Android screenshot fixture did not become ready." >&2
    return 1
  fi

  # The in-app marker confirms that Flutter has rendered the target page.
  # Give SystemUI one more beat to finish applying demo-mode status bars before
  # capturing the complete physical display.
  sleep 1
  adb -s "$android_device_id" exec-out screencap -p >"$output"
  kill -INT "$flutter_pid" >/dev/null 2>&1 || true
  wait "$flutter_pid" >/dev/null 2>&1 || true
  adb -s "$android_device_id" shell am force-stop dev.sitesignal.app || true
  disable_android_demo_mode
  rm -f "$capture_log"
  test -s "$output"
}

case "$target" in
  macos)
    capture_macos overview
    capture_macos history
    capture_macos settings
    ;;
  android)
    capture_android overview
    capture_android history
    capture_android settings
    ;;
  *)
    echo "Usage: $0 <macos|android>" >&2
    exit 64
    ;;
esac
