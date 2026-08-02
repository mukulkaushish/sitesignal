#!/bin/sh

set -eu

site_signal_project_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
)
site_signal_requested_arch=${1:-$(uname -m)}

case "$site_signal_requested_arch" in
  arm64|aarch64)
    site_signal_artifact_arch=arm64
    site_signal_flutter_arch=arm64
    ;;
  x86_64|x64)
    site_signal_artifact_arch=x86_64
    site_signal_flutter_arch=x64
    ;;
  *)
    echo "Usage: $0 [arm64|aarch64|x86_64|x64]" >&2
    exit 64
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) site_signal_host_arch=arm64 ;;
  x86_64|x64) site_signal_host_arch=x86_64 ;;
  *)
    echo "Unsupported Linux host architecture: $(uname -m)" >&2
    exit 64
    ;;
esac

if [ "$site_signal_artifact_arch" != "$site_signal_host_arch" ]; then
  echo "Flutter Linux desktop builds must match the host architecture." >&2
  exit 64
fi

site_signal_bundle="$site_signal_project_dir/build/linux/$site_signal_flutter_arch/release/bundle"
site_signal_output_dir="$site_signal_project_dir/build/distributions/linux/$site_signal_artifact_arch"
site_signal_output_bundle="$site_signal_output_dir/SiteSignal"
site_signal_output_archive="$site_signal_output_dir/SiteSignal-linux-$site_signal_artifact_arch.tar.gz"
site_signal_symbols_dir="$site_signal_project_dir/build/debug-symbols/linux"

cd "$site_signal_project_dir"
flutter build linux --release --split-debug-info="$site_signal_symbols_dir"

if [ ! -d "$site_signal_bundle" ]; then
  echo "Flutter did not create the expected bundle: $site_signal_bundle" >&2
  exit 1
fi

mkdir -p "$site_signal_output_dir"
if [ -e "$site_signal_output_bundle" ]; then
  rm -rf -- "$site_signal_output_bundle"
fi
rm -f -- "$site_signal_output_archive"
mkdir -p "$site_signal_output_bundle"
cp -a "$site_signal_bundle/." "$site_signal_output_bundle/"
mkdir -p \
  "$site_signal_output_bundle/share/applications" \
  "$site_signal_output_bundle/share/icons/hicolor/512x512/apps"
cp \
  "$site_signal_project_dir/linux/packaging/dev.sitesignal.SiteSignal.desktop" \
  "$site_signal_output_bundle/share/applications/"
cp \
  "$site_signal_project_dir/assets/app_icon.png" \
  "$site_signal_output_bundle/share/icons/hicolor/512x512/apps/dev.sitesignal.SiteSignal.png"

if [ ! -x "$site_signal_output_bundle/site_signal" ]; then
  echo "SiteSignal executable is missing from the Linux bundle." >&2
  exit 1
fi

if [ ! -f "$site_signal_output_bundle/lib/libsqlite3.so" ]; then
  echo "Bundled SQLite runtime is missing from the Linux release." >&2
  exit 1
fi

if [ ! -f "$site_signal_output_bundle/share/applications/dev.sitesignal.SiteSignal.desktop" ]; then
  echo "Linux desktop integration is missing from the release bundle." >&2
  exit 1
fi

tar -C "$site_signal_output_dir" \
  -czf "$site_signal_output_archive" \
  SiteSignal

du -sh "$site_signal_output_bundle" "$site_signal_output_archive"
