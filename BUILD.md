# Build and release SiteSignal

Run commands from the repository root. SiteSignal 1.0.0 uses Flutter 3.44.7
and Dart 3.12.

## Prepare the toolchain

Install Flutter and the native tools for the platform you want to build. Native
desktop packages must be created on that operating system.

```bash
flutter --version
flutter doctor -v
flutter pub get
```

Before packaging, run the same checks used by CI:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test tool
bash -n tool/*.sh
dart run tool/check_code_rules.dart
flutter analyze
flutter test --coverage
```

The reusable quality workflow also checks GitHub Actions syntax, requires at
least 75% line coverage, and rejects unpinned third-party actions.

## Version 1.0.0

The application and Windows package versions are declared in `pubspec.yaml`:

```yaml
version: 1.0.0+1

msix_config:
  msix_version: 1.0.0.1
```

The part before `+` is the public release version. The build number becomes the
fourth MSIX version component. `tool/check_code_rules.dart` verifies that these
values stay aligned.

## Local packages

The build coordinator accepts one target at a time:

```bash
dart run tool/build_all_platforms.dart --target android --arch all
dart run tool/build_all_platforms.dart --target macos --arch all
dart run tool/build_all_platforms.dart --target linux --arch "$(uname -m)"
```

On Windows PowerShell:

```powershell
dart run tool/build_all_platforms.dart --target windows --arch x86_64
```

Use `arm64` on an ARM64 Windows runner. Linux packages must also match the host
architecture. All outputs are written below `build/distributions/`, which is
ignored by Git.

### Linux dependencies

On Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libstdc++-12-dev libayatana-appindicator3-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Package directly on an x86_64 or ARM64 host:

```bash
tool/package_linux_release.sh x86_64
tool/package_linux_release.sh arm64
```

Each command creates a `SiteSignal-linux-<architecture>.tar.gz` containing the
executable, libraries, and Flutter data. Keep the extracted directories
together. Desktop alerts require a graphical user session and its standard
Freedesktop notification service. A GNOME tray icon may require the AppIndicator
extension.

### macOS

Install Xcode and its command-line tools, then run on Apple silicon or Intel:

```bash
tool/package_macos_minimal.sh "$(uname -m)"
```

The script accepts `arm64` and `x86_64`, thins Flutter's application to that
architecture, applies an ad-hoc signature, and creates
`SiteSignal-macos-<architecture>.zip`. Public Developer ID signing and Apple
notarization are not included.

Verify a local application with:

```bash
codesign --verify --deep --strict \
  build/distributions/macos/arm64/SiteSignal.app
lipo -archs \
  build/distributions/macos/arm64/SiteSignal.app/Contents/MacOS/SiteSignal
```

### Windows

Install Flutter desktop support and Visual Studio's **Desktop development with
C++** workload. In PowerShell, use `x64` or `arm64`:

```powershell
./tool/package_windows_release.ps1 x64
./tool/package_windows_release.ps1 arm64
```

Each build creates a portable ZIP and a development MSIX. Keep the executable,
DLLs, and `data/` directory together when using the ZIP. A public MSIX needs a
trusted publisher certificate or Store signing.

Windows restricts custom toast audio to packaged applications. The portable ZIP
can fall back to the system sound for delivered notifications, although the
sound picker preview still plays the selected bundled tone in the app.

### Android

Install the Android SDK components reported by `flutter doctor` and Java 17.
The release coordinator creates three split APKs:

```bash
dart run tool/build_all_platforms.dart --target android --arch all
```

The repository uses development signing. Configure a protected production
keystore before publishing to a store. Automatic checks use a visible Android
foreground service because the operating system limits hidden background work.

Android 8 and newer keep notification-channel sound choices after a channel is
created. SiteSignal uses separate versioned channels for each sound. The device
owner's channel settings and Do Not Disturb remain authoritative, so test alerts
on real hardware before relying on them.

## Screenshots

Repository screenshots use the real Flutter engine and fixed `example.com`
fixtures. Capture the macOS collection with:

```bash
./tool/capture_repository_screenshots.sh macos
```

Start an Android emulator, then capture its collection with:

```bash
ANDROID_DEVICE_ID=emulator-5554 \
  ./tool/capture_repository_screenshots.sh android
```

The entry point is `tool/repository_screenshot_main.dart`. macOS produces 2×
images. Android uses `adb screencap`, includes the status and navigation bars,
and uses SystemUI demo mode for deterministic status indicators. The six
checked-in files are the Overview, History, and Settings pages in light mode.
CI regenerates them and fails when they differ; it never commits as a bot.

## Free GitHub Actions pipeline

SiteSignal uses only standard GitHub-hosted runners and the repository's built-in
token. Standard runner usage is free while this repository is public. GitHub's
usage, artifact-retention, and storage policies still apply; workflow artifacts
are intentionally retained for only one day.

`.github/workflows/quality.yml` is shared by CI and releases. It runs formatting,
shell validation, repository rules, static analysis, tests, and coverage.

`.github/workflows/ci.yml` runs on pull requests and `main`. After the quality
gate it:

- runs the Android device feature flow;
- regenerates the three Android light screenshots;
- regenerates the three macOS light screenshots; and
- fails if any checked-in screenshot is stale.

`.github/workflows/release.yml` runs manually or for a `v*` tag. It builds these
11 packages:

| Platform | Packages |
| --- | --- |
| Android | ARMv7 APK, ARM64 APK, x86_64 APK |
| Linux | ARM64 `tar.gz`, x86_64 `tar.gz` |
| macOS | ARM64 ZIP, x86_64 ZIP |
| Windows | ARM64 ZIP and MSIX, x86_64 ZIP and MSIX |

The publish job requires exactly those 11 files, writes basename-only SHA-256
entries to `SHA256SUMS.txt`, and uploads all 12 assets to one stable GitHub
release. A manual run builds downloadable workflow artifacts but does not create
a release.

The build and release matrix does not create an iOS package.

## Publish 1.0.0

The release tag must be exactly `v1.0.0`. The quality gate compares it with the
public version in `pubspec.yaml` and stops before packaging if they differ.

```bash
git tag -a v1.0.0 -m "SiteSignal 1.0.0"
git push origin v1.0.0
```

The tag starts the complete native matrix. The release appears only after every
quality, device, build, package-count, and checksum check succeeds.

## Prepare version 1.0.1

1. Update `CHANGELOG.md`.
2. Change these exact values in `pubspec.yaml`:

   ```yaml
   version: 1.0.1+2

   msix_config:
     msix_version: 1.0.1.2
   ```

3. Run the local quality checks, commit, and push `main`:

   ```bash
   git add pubspec.yaml CHANGELOG.md
   git commit -m "chore: prepare 1.0.1 release"
   git push origin main
   ```

4. Wait for CI to pass, then create and push an annotated tag:

   ```bash
   git tag -a v1.0.1 -m "SiteSignal 1.0.1"
   git push origin v1.0.1
   ```

The tag/version guard rejects an accidental tag such as `v1.0.1` while
`pubspec.yaml` still says `1.0.0`. Do not move a published tag; fix the version,
commit it, and create the correct new tag.

## Release smoke checks

Before announcing a release:

1. Verify `SHA256SUMS.txt` against the downloaded package.
2. Open the application and add a disposable test monitor.
3. Send a test notification for a bundled sound and for the system sound.
4. Trigger one outage and recovery on a real device.
5. Confirm pause/resume, tray or foreground-service behavior, and local history.

Emulators can verify the feature flow, but they cannot prove that native audio,
notification permissions, Do Not Disturb, battery policy, sleep/wake, or every
desktop environment behaves correctly.
