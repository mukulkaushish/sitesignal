#!/bin/sh

set -eu

site_signal_project_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
)
site_signal_requested_arch=${1:-$(uname -m)}

case "$site_signal_requested_arch" in
  all)
    site_signal_arches="arm64 x86_64"
    ;;
  arm64|x86_64)
    site_signal_arches=$site_signal_requested_arch
    ;;
  *)
    echo "Usage: $0 [all|arm64|x86_64]" >&2
    exit 64
    ;;
esac

site_signal_source_app="$site_signal_project_dir/build/macos/Build/Products/Release/SiteSignal.app"
site_signal_symbols_dir="$site_signal_project_dir/build/debug-symbols/macos"

cd "$site_signal_project_dir"
flutter build macos --release --split-debug-info="$site_signal_symbols_dir"

if [ ! -d "$site_signal_source_app" ]; then
  echo "Flutter did not create the expected app: $site_signal_source_app" >&2
  exit 1
fi

# Run each package in a subshell so its architecture-specific variables do not
# leak into the next package when "all" is requested.
site_signal_package_architecture() (
  site_signal_arch=$1
  site_signal_output_dir="$site_signal_project_dir/build/distributions/macos/$site_signal_arch"
  site_signal_output_app="$site_signal_output_dir/SiteSignal.app"
  site_signal_output_zip="$site_signal_output_dir/SiteSignal-macos-$site_signal_arch.zip"

  mkdir -p "$site_signal_output_dir"
  if [ -e "$site_signal_output_app" ]; then
    rm -rf -- "$site_signal_output_app"
  fi
  rm -f -- "$site_signal_output_zip"
  ditto "$site_signal_source_app" "$site_signal_output_app"

  site_signal_thin_binary() {
    site_signal_binary=$1
    if ! lipo "$site_signal_binary" -verify_arch "$site_signal_arch"; then
      echo "Missing $site_signal_arch slice: $site_signal_binary" >&2
      exit 1
    fi
    lipo "$site_signal_binary" \
      -thin "$site_signal_arch" \
      -output "$site_signal_binary.thin"
    mv "$site_signal_binary.thin" "$site_signal_binary"
  }

  site_signal_thin_binary "$site_signal_output_app/Contents/MacOS/SiteSignal"
  site_signal_thin_binary \
    "$site_signal_output_app/Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS"
  site_signal_thin_binary \
    "$site_signal_output_app/Contents/Frameworks/App.framework/Versions/A/App"
  site_signal_thin_binary \
    "$site_signal_output_app/Contents/Frameworks/objective_c.framework/Versions/A/objective_c"
  site_signal_thin_binary \
    "$site_signal_output_app/Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3"

  # The Xcode release still carries local symbols in its tiny native runner.
  strip -x "$site_signal_output_app/Contents/MacOS/SiteSignal"

  # Thinning invalidates the local development signature. An ad-hoc signature
  # keeps the artifact launchable for local verification; distribution signing
  # and notarization should replace it with the publisher's Developer ID.
  codesign --force --deep --sign - --timestamp=none \
    --entitlements "$site_signal_project_dir/macos/Runner/Release.entitlements" \
    "$site_signal_output_app"
  codesign --verify --deep --strict "$site_signal_output_app"

  ditto -c -k --sequesterRsrc --keepParent \
    "$site_signal_output_app" \
    "$site_signal_output_zip"

  du -sh "$site_signal_output_app" "$site_signal_output_zip"
)

for site_signal_arch in $site_signal_arches; do
  site_signal_package_architecture "$site_signal_arch"
done
