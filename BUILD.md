# Building SiteSignal

Run all commands from the repository root.

## Requirements

- Flutter 3.44.7 (the CI-pinned version) or newer within the 3.44 stable line
- Dart 3.12 or newer
- Git
- A native build environment for the requested target. Windows builds require
  Windows; Apple builds require macOS with Xcode; Linux builds require Linux.

Confirm the toolchain and install the Dart dependencies:

```bash
flutter --version
flutter doctor -v
flutter pub get
```

Before packaging a release, run the project checks:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test tool
dart run tool/check_code_rules.dart
flutter analyze
flutter test
```

The application version is set in `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

Update it before creating a new release when appropriate. SiteSignal reads the
installed version and build number at runtime; widgets must not contain a
hardcoded release string. Keep `msix_config.msix_version` aligned as
`major.minor.patch.build`; `tool/check_code_rules.dart` validates the mapping,
canonical platform identity, required icon assets, and sound-copy parity.

## Linux build dependencies

On Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libstdc++-12-dev libayatana-appindicator3-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Flutter Linux desktop builds must match the host architecture. Check the
current Linux machine with:

```bash
uname -m
```

Use an x86_64 Linux host for an x86_64 build and an ARM64 Linux host for an
ARM64 build.

### Linux x86_64

Run this on an x86_64 Linux machine:

```bash
tool/package_linux_release.sh x86_64
```

Output:

```text
build/distributions/linux/x86_64/SiteSignal/
build/distributions/linux/x86_64/SiteSignal-linux-x86_64.tar.gz
```

### Linux ARM64

Run this on an ARM64 Linux machine:

```bash
tool/package_linux_release.sh arm64
```

`aarch64` is also accepted.

Output:

```text
build/distributions/linux/arm64/SiteSignal/
build/distributions/linux/arm64/SiteSignal-linux-arm64.tar.gz
```

### Verify a Linux artifact

For x86_64:

```bash
gzip -t build/distributions/linux/x86_64/SiteSignal-linux-x86_64.tar.gz
tar -tzf build/distributions/linux/x86_64/SiteSignal-linux-x86_64.tar.gz
file build/distributions/linux/x86_64/SiteSignal/site_signal
file build/distributions/linux/x86_64/SiteSignal/lib/libsqlite3.so
sha256sum build/distributions/linux/x86_64/SiteSignal-linux-x86_64.tar.gz
```

Both `file` results must report x86-64 ELF binaries. For ARM64, use the
corresponding `arm64` paths and confirm that both report `ARM aarch64`.

To run the packaged application:

```bash
tar -xzf SiteSignal-linux-x86_64.tar.gz
cd SiteSignal
./site_signal
```

Keep the executable, `lib/`, and `data/` directories together.

## Linux notifications and tray behavior

Linux desktop notifications are supported. SiteSignal sends them through the
desktop session's standard `org.freedesktop.Notifications` D-Bus service. A
normal graphical Ubuntu, GNOME, KDE, Cinnamon, or similar desktop session
usually provides this service automatically.

Notifications require:

- SiteSignal to remain running; closing its dashboard keeps it running in the
  system tray, while quitting it stops monitoring
- A graphical user session with a working session D-Bus
- A desktop notification service with notifications and Do Not Disturb
  configured to allow alerts

SiteSignal deliberately sends no notification for the first result, because
that result establishes the baseline. It then notifies only on real
`up → down` and `down → up` transitions. Use **Settings → Notifications →
Send test** to verify delivery on the target Linux desktop.

Selecting a bundled tone, or sending its test notification, plays that exact
asset in-app. Transition notifications still request their sound through the
Freedesktop server, which may substitute or suppress it based on desktop
capabilities, notification preferences, silent mode, or Do Not Disturb.

On plain GNOME installations, the tray icon may additionally require the
[AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/).
That extension affects the tray icon; desktop notifications use the separate
notification service.

If notifications do not appear, first disable Do Not Disturb and test whether
the desktop notification service is reachable:

```bash
gdbus call --session \
  --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.GetServerInformation
```

Notifications are not expected to work in a headless shell, an SSH session
without the user's session bus, or a container without access to the graphical
desktop session.

## Launch at system startup

The **Settings → Desktop behavior → Open at system startup** toggle registers
SiteSignal for the current user only. The operating system remains the source
of truth, so the toggle reflects external changes made in system settings.

- macOS 13+ uses `SMAppService.mainApp`. Install the packaged app normally
  before enabling it. Older supported macOS releases can still run SiteSignal,
  but do not expose this toggle.
- Linux writes the standard per-user
  `~/.config/autostart/SiteSignal.desktop` entry.
- Windows uses the current-user startup registration for portable builds and a
  Startup-folder shortcut when running with MSIX package identity.

## macOS build

Install Xcode and its command-line tools, then run:

```bash
tool/package_macos_minimal.sh "$(uname -m)"
```

The script accepts `arm64` and `x86_64`.

Output:

```text
build/distributions/macos/<architecture>/SiteSignal.app
build/distributions/macos/<architecture>/SiteSignal-macos-<architecture>.zip
```

The script builds the normal universal Flutter application, thins it to the
requested architecture, applies an ad-hoc local signature, and creates the ZIP
archive. Public distribution still requires a Developer ID signature and Apple
notarization.

Verify a local macOS package with:

```bash
codesign --verify --deep --strict \
  build/distributions/macos/arm64/SiteSignal.app
lipo -archs \
  build/distributions/macos/arm64/SiteSignal.app/Contents/MacOS/SiteSignal
```

Adjust the path to `x86_64` when building for Intel macOS.

## Windows x86_64 build

Install Flutter with Windows desktop support and Visual Studio's **Desktop
development with C++** workload. From PowerShell, run:

```powershell
./tool/package_windows_release.ps1 x64
```

Output:

```text
build/distributions/windows/x86_64/SiteSignal/
build/distributions/windows/x86_64/SiteSignal-windows-x86_64.zip
build/distributions/windows/x86_64/SiteSignal-windows-x86_64.msix
```

The packaging script fails if either `site_signal.exe` or the bundled
`sqlite3.dll` is absent. Keep the executable, DLLs, and `data/` directory
together when distributing an extracted build. Windows restricts custom toast
audio to apps with package identity, so delivered notifications from the
portable ZIP fall back to the system sound. Picker and test-notification
previews play the chosen bundled tone in-app in both distributions. The
development MSIX uses a test certificate. Public distribution requires a
trusted publisher certificate or Microsoft Store signing.

## Android build

Install Android Studio/SDK components reported by `flutter doctor`, use Java
17, and run:

```bash
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The repository's release configuration uses a debug key only for development
artifacts. Configure a protected production keystore before publishing the APK
or an app bundle.

Automatic monitoring uses an Android `specialUse` foreground service. It shows
a low-importance persistent status notification, keeps automatic checks running
when the UI is backgrounded, and can restart after reboot or package update.
Google Play requires the matching foreground-service declaration and review;
the manifest describes the subtype as user-enabled website health monitoring.
Do not change it to `dataSync`: Android 15 limits that service type to six hours
per 24 hours and prevents it from starting at boot.

Android 8+ freezes a notification channel's sound after first creation. Each
SiteSignal sound therefore has a separate versioned high-importance channel.
The picker and test notification play bundled selections directly, and request
the current default notification ringtone natively for **System default**. This
keeps each preview faithful instead of letting an existing channel substitute
another sound. Delivered transition alerts still use the selected channel, and
operating-system/user channel settings remain authoritative. If a real alert is
quiet, open Android notification settings and confirm that the selected
SiteSignal channel allows sound and is not affected by Do Not Disturb.

Hardware smoke test:

1. Enable notifications and automatic monitoring; confirm the persistent
   **SiteSignal monitoring** status remains after leaving the app.
2. Turn off Wi-Fi and mobile data, or join Wi-Fi without internet. Confirm one
   **No network** or **No internet** alert and verify sites are not marked down.
3. Keep the device offline and confirm no per-site or repeated connectivity
   alerts appear.
4. Restore internet and confirm one **Internet restored** alert, then verify
   overdue website checks resume.
5. Lock the phone for longer than a site's interval and confirm its latest-check
   time advances from the foreground service.

Desktop sleep/wake smoke test:

1. Leave an enabled site healthy, then put the laptop to sleep during a check.
2. Wake it after several intervals and confirm SiteSignal runs one fresh overdue
   check rather than replaying missed checks.
3. Confirm the sleep-spanning request did not create a false outage or duplicate
   notification.

## iOS distribution status

iOS distribution is intentionally disabled for now. The application source and
runner remain available for future platform work, but
`tool/build_all_platforms.dart`, CI, manual release runs, and tagged releases do
not create or publish an iOS artifact.

## Zero-cost CI/CD

The workflows use only standard GitHub-hosted runners. GitHub Actions usage on
those runners is free while SiteSignal remains public. No external CI service,
paid larger runner, package registry, or dependency cache is required.

The regular `.github/workflows/ci.yml` pipeline runs for pull requests and
pushes to `main`:

1. GitHub Actions linting, format checks, shell syntax checks, repository rules,
   static analysis, and the complete Flutter test suite with an LCOV report.
2. One Apple-silicon macOS package and Android split APKs for ARMv7, ARM64, and
   x86_64.
3. Native-engine light-mode screenshots of Overview, History, and Settings on
   macOS and an Android Pixel 4a emulator using sanitized sample monitors. The
   Android emulator also runs the complete end-to-end feature flow.
4. Screenshot artifacts for visual review. Contributors commit regenerated
   images themselves; CI never creates a bot-authored commit.

Normal build and coverage artifacts expire after seven days. Superseded runs on
the same branch are canceled. Flutter and emulator caches are deliberately not
stored, avoiding persistent cache growth in exchange for slightly longer free
runner time.

### Reproduce visual assets locally

On macOS:

```bash
./tool/capture_repository_screenshots.sh macos
```

Start an Android emulator, identify it with `flutter devices`, then run:

```bash
ANDROID_DEVICE_ID=emulator-5554 \
  ./tool/capture_repository_screenshots.sh android
```

The commands replace exactly these files:

```text
docs/screenshots/macos-overview-light.png
docs/screenshots/macos-history-light.png
docs/screenshots/macos-settings-light.png
docs/screenshots/android-overview-light.png
docs/screenshots/android-history-light.png
docs/screenshots/android-settings-light.png
```

The Flutter entry point is `test/screenshot_main.dart`. macOS writes a 2× PNG
from a root `RepaintBoundary` in the actual platform engine, so capture does not
need Screen Recording permission and does not use Flutter's placeholder test
font. Android uses `adb screencap` at the emulator's native 1080×2340 display
resolution, which includes the real status and navigation bars. The capture
script enables Android SystemUI demo mode so the clock, battery, and network
icons remain deterministic across CI runs.

CI also runs `integration_test/feature_flow_test.dart` on the Android emulator
to exercise the complete feature flow.

### Full native release matrix

Run **Actions → Release → Run workflow** to build every target without creating
a GitHub release:

- Linux x86_64 on `ubuntu-latest`
- Linux ARM64 on `ubuntu-24.04-arm`
- macOS ARM64 and x86_64 on `macos-26`
- Windows x86_64 on `windows-latest`
- Windows ARM64 on `windows-11-arm`
- Android ARMv7, ARM64, and x86_64 APKs on `ubuntu-latest`

The workflow exposes architecture-named artifacts for one day. This expensive
matrix is intentionally manual or release-only instead of running for every
documentation edit.

### Publish a prerelease

After updating the application version and changelog, create and push a `v*`
tag. For example:

```bash
git tag -s v1.0.0 -m "SiteSignal 1.0.0"
git push origin v1.0.0
```

The same quality gate and complete matrix must pass. The workflow combines the
packages, creates `SHA256SUMS.txt`, and publishes them to a
GitHub prerelease using the repository's built-in token. GitHub release
downloads do not depend on the short-lived workflow artifacts.

The free outputs are intentionally labeled as prereleases:

- macOS archives are ad-hoc signed. Developer ID signing and Apple notarization
  require a paid Apple Developer Program membership.
- Android APKs currently use the repository's development signing setup. A
  production keystore can be generated without paying a store, but its private
  key must be protected outside the repository.
- Windows MSIX is development signed.

Users can download Android APKs and the macOS archive directly from GitHub at no
hosting cost, but operating systems may show warnings for these development
artifacts. Do not relabel them as production-signed builds.
