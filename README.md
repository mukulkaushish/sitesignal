<h1 align="center">SiteSignal</h1>

<p align="center">
  <a href="https://github.com/mukulkaushish/sitesignal">
    <img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/assets/app_icon.png" width="152" height="152" alt="SiteSignal app icon">
  </a>
</p>

<p align="center">
  <strong>Know when your website goes down—and when it comes back.</strong>
  <br>
  A free, local-first website monitor for your own devices.
</p>

<p align="center">
  <a href="https://github.com/mukulkaushish/sitesignal/actions/workflows/ci.yml"><img src="https://github.com/mukulkaushish/sitesignal/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="https://github.com/mukulkaushish/sitesignal/releases/latest"><img src="https://img.shields.io/github/v/release/mukulkaushish/sitesignal?display_name=tag&sort=semver" alt="Latest release"></a>
  <a href="https://github.com/mukulkaushish/sitesignal/blob/main/LICENSE"><img src="https://img.shields.io/github/license/mukulkaushish/sitesignal" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/Flutter-3.44.7-02569B?logo=flutter&logoColor=white" alt="Flutter 3.44.7">
</p>

<p align="center">
  <a href="https://github.com/mukulkaushish/sitesignal/releases/latest"><strong>Download the latest release</strong></a>
  ·
  <a href="https://github.com/mukulkaushish/sitesignal/issues">Report a problem</a>
  ·
  <a href="BUILD.md">Build it yourself</a>
</p>

SiteSignal checks the websites you choose and sends a native notification when
their state changes. There is no account, cloud dashboard, analytics, advertising,
or subscription. Your settings and history stay on your device.

## Screenshots

These light-mode screenshots use safe `example.com` demo data and are always
visible. Select any image to open the original high-resolution file.

### macOS

#### Overview

<p align="center">
  <a href="https://github.com/mukulkaushish/sitesignal/blob/main/docs/screenshots/macos-overview-light.png">
    <img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/docs/screenshots/macos-overview-light.png" width="900" alt="SiteSignal overview on macOS">
  </a>
</p>

<table>
  <tr>
    <th width="50%">History</th>
    <th width="50%">Settings</th>
  </tr>
  <tr>
    <td><a href="https://github.com/mukulkaushish/sitesignal/blob/main/docs/screenshots/macos-history-light.png"><img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/docs/screenshots/macos-history-light.png" width="440" alt="SiteSignal history on macOS"></a></td>
    <td><a href="https://github.com/mukulkaushish/sitesignal/blob/main/docs/screenshots/macos-settings-light.png"><img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/docs/screenshots/macos-settings-light.png" width="440" alt="SiteSignal settings on macOS"></a></td>
  </tr>
</table>

### Android

<table>
  <tr>
    <th width="33%">Overview</th>
    <th width="33%">History</th>
    <th width="33%">Settings</th>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/mukulkaushish/sitesignal/blob/main/docs/screenshots/android-overview-light.png"><img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/docs/screenshots/android-overview-light.png" width="260" alt="SiteSignal overview on Android"></a></td>
    <td align="center"><a href="https://github.com/mukulkaushish/sitesignal/blob/main/docs/screenshots/android-history-light.png"><img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/docs/screenshots/android-history-light.png" width="260" alt="SiteSignal history on Android"></a></td>
    <td align="center"><a href="https://github.com/mukulkaushish/sitesignal/blob/main/docs/screenshots/android-settings-light.png"><img src="https://raw.githubusercontent.com/mukulkaushish/sitesignal/main/docs/screenshots/android-settings-light.png" width="260" alt="SiteSignal settings on Android"></a></td>
  </tr>
</table>

## What it does

- Monitors multiple HTTP or HTTPS websites on a schedule.
- Discovers safe same-origin health endpoints such as `/health`, `/healthz`,
  `/livez`, `/readyz`, `/api/health`, and `/status`.
- Shows response time, HTTP status, uptime, and state-change history.
- Avoids false outage records when the device itself has no internet access.
- Sends alerts only for real changes: online to offline, or offline to online.
- Offers four bundled notification sounds, the system sound, and silent mode.
- Plays a sound preview when you select it and uses that choice for test alerts.
- Keeps desktop monitoring in the system tray and Android monitoring in a visible
  foreground service.
- Stores configuration and a bounded history in a local SQLite database.

## Downloads

The [latest GitHub release](https://github.com/mukulkaushish/sitesignal/releases/latest)
contains checksummed packages built by the repository workflow.

| Platform | Architectures | Packages |
| --- | --- | --- |
| Android | ARMv7, ARM64, x86_64 | APK |
| macOS | ARM64, x86_64 | ZIP |
| Linux | ARM64, x86_64 | `tar.gz` |
| Windows | ARM64, x86_64 | ZIP and MSIX |

The packages are unsigned, ad-hoc signed, or development signed. Your operating
system may show an installation warning. See [BUILD.md](BUILD.md) for exact
targets, verification, and local build commands.

## How it works

1. Add a website and choose a check interval.
2. SiteSignal checks its base address and safe same-origin health paths.
3. A `200–299` response is healthy. Other responses and connection failures are
   unhealthy.
4. The first result creates a baseline. Later state changes create a history
   entry and notification.
5. Everything is saved locally on the device.

SiteSignal is useful for personal sites, side projects, homelabs, and internal
tools. It checks from one device and one network, so it is not a replacement for
multi-region monitoring or a public status page.

## Privacy

SiteSignal has no hosted backend. It sends requests only to sites you configure,
same-origin discovery resources, and small public connectivity endpoints used to
tell a device outage from a website outage. It never sends your monitor list or
history to a SiteSignal service.

Read [PRIVACY.md](PRIVACY.md) for the complete data-flow and retention details.

## Quick start

Install Flutter 3.44.7 and the native toolchain for your platform, then run:

```bash
git clone https://github.com/mukulkaushish/sitesignal.git
cd sitesignal
flutter pub get
flutter run
```

Run the main checks with:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test tool
bash -n tool/*.sh
dart run tool/check_code_rules.dart
flutter analyze
flutter test
```

Device tests stay in `integration_test/`; unit and widget tests stay in `test/`.
See [the architecture guide](docs/architecture.md), [BUILD.md](BUILD.md), and
[CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Contributing

Issues and pull requests are welcome. Keep changes focused, add regression tests,
and use only sanitized `example.com` data in screenshots, logs, and reports.
Please read [CONTRIBUTING.md](CONTRIBUTING.md),
[SECURITY.md](SECURITY.md), and the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

SiteSignal is open source under the [MIT License](LICENSE).
