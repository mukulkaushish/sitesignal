#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
walkthrough_directory="$project_directory/docs/walkthrough"
android_device_id="${ANDROID_DEVICE_ID:-emulator-5554}"
target="${1:-}"

if [[ "$target" != android ]]; then
  echo "Usage: $0 android" >&2
  exit 64
fi

mkdir -p "$walkthrough_directory"
cd "$project_directory"

output="$walkthrough_directory/sitesignal-android.mp4"
remote_output="/sdcard/sitesignal-android-walkthrough.mp4"
test_log="$(mktemp)"
record_log="$(mktemp)"
test_pid=""
record_pid=""

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

cleanup() {
  if [[ -n "$record_pid" ]] && kill -0 "$record_pid" >/dev/null 2>&1; then
    local remote_pid
    remote_pid="$(
      adb -s "$android_device_id" shell pidof screenrecord 2>/dev/null \
        | tr -d '\r' || true
    )"
    if [[ -n "$remote_pid" ]]; then
      adb -s "$android_device_id" shell kill -2 "$remote_pid" >/dev/null 2>&1 || true
    fi
    wait "$record_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$test_pid" ]] && kill -0 "$test_pid" >/dev/null 2>&1; then
    kill -INT "$test_pid" >/dev/null 2>&1 || true
    wait "$test_pid" >/dev/null 2>&1 || true
  fi
  adb -s "$android_device_id" shell settings put system show_touches 0 \
    >/dev/null 2>&1 || true
  adb -s "$android_device_id" shell am broadcast \
    -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true
  adb -s "$android_device_id" shell rm -f "$remote_output" \
    >/dev/null 2>&1 || true
  rm -f "$test_log" "$record_log"
}
trap cleanup EXIT

adb -s "$android_device_id" shell rm -f "$remote_output"
adb -s "$android_device_id" shell settings put system show_touches 1
enable_android_demo_mode

flutter test integration_test/walkthrough_test.dart \
  --device-id "$android_device_id" >"$test_log" 2>&1 &
test_pid=$!

ready=false
for _ in $(seq 1 180); do
  if grep -q 'WALKTHROUGH_READY' "$test_log"; then
    ready=true
    break
  fi
  if ! kill -0 "$test_pid" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [[ "$ready" != true ]]; then
  cat "$test_log" >&2
  echo "Walkthrough test did not become ready." >&2
  exit 1
fi

adb -s "$android_device_id" shell screenrecord \
  --bit-rate 1200000 \
  --time-limit 180 \
  "$remote_output" >"$record_log" 2>&1 &
record_pid=$!

set +e
wait "$test_pid"
test_status=$?
set -e
test_pid=""

remote_pid="$(
  adb -s "$android_device_id" shell pidof screenrecord 2>/dev/null \
    | tr -d '\r' || true
)"
if [[ -n "$remote_pid" ]]; then
  adb -s "$android_device_id" shell kill -2 "$remote_pid" >/dev/null 2>&1 || true
fi
wait "$record_pid" >/dev/null 2>&1 || true
record_pid=""

if [[ "$test_status" -ne 0 ]] || ! grep -q 'WALKTHROUGH_COMPLETE' "$test_log"; then
  cat "$test_log" >&2
  echo "Walkthrough integration test failed." >&2
  exit 1
fi

if ! adb -s "$android_device_id" shell test -s "$remote_output"; then
  cat "$record_log" >&2
  echo "Android did not produce a walkthrough recording." >&2
  exit 1
fi

adb -s "$android_device_id" pull "$remote_output" "$output" >/dev/null
test -s "$output"

size_bytes="$(stat -f '%z' "$output" 2>/dev/null || stat -c '%s' "$output")"
if [[ "$size_bytes" -gt 10000000 ]]; then
  echo "Walkthrough exceeds GitHub's 10 MB free-account video limit." >&2
  exit 1
fi

echo "WALKTHROUGH_SAVED=$output"
