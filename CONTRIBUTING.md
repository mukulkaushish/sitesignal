# Contributing to SiteSignal

Thank you for helping improve SiteSignal. Contributions are welcome across
Flutter UI, health-check correctness, native platform integration,
documentation, accessibility, testing, and packaging.

## Before opening an issue

- Search existing issues to avoid duplicates.
- Use the bug or feature template so the report contains enough context.
- Remove real monitor URLs, credentials, response bodies, notification
  contents, signing files, and other private data from screenshots or logs.
- Use the private process in [SECURITY.md](SECURITY.md) for vulnerabilities.

Questions about expected platform behavior may already be answered in
[README.md](README.md) or [BUILD.md](BUILD.md).

## Development setup

Install the Flutter version listed in [BUILD.md](BUILD.md), then run:

```bash
flutter pub get
flutter run -d <device-id>
```

Replace `<device-id>` with `macos`, `linux`, `windows`, an Android device, or an
iOS device. Native desktop releases must be built on the matching host
operating system. Apple releases require macOS and Xcode.

## Project structure

SiteSignal uses a feature-first, ports-and-adapters design:

- `lib/features/monitoring/domain` contains platform-neutral entities, ports,
  and pure policy.
- `lib/features/monitoring/data` contains HTTP, SQLite, plugin, background, and
  operating-system adapters.
- `lib/features/monitoring/presentation` contains controller state and Flutter
  views.
- `lib/core` contains shared async, theme, platform, text, and widget code.
- `test` mirrors the production behavior with unit, adapter, controller, and
  responsive widget coverage.

Read [CLAUDE.md](CLAUDE.md) before modifying code. Despite its filename, it is
the repository-wide engineering standard for every contributor and coding
assistant.

## Core correctness rules

- A device connectivity failure must never mark a monitored website down.
- The first result establishes a baseline; only later state changes notify.
- Persist a transition before sending its notification.
- Keep network work bounded and coalesce concurrent checks for the same site.
- Revalidate mutable state after asynchronous boundaries before applying a
  result.
- Keep domain code free of plugins, SQL, `dart:io`, and platform checks.
- Never expose a monitored URL, response body, credential, or private history
  in logs, issues, screenshots, or notification copy.
- Do not add postfix null assertions in Dart, Kotlin, or Swift.
- Use shared theme tokens and native system typography.
- Regenerate icons and sounds from their checked-in generators instead of
  editing platform copies individually.

The complete invariant list and reasoning are in [CLAUDE.md](CLAUDE.md).

## Making a change

1. Keep the change focused on one problem.
2. Follow an existing repository pattern before creating a new abstraction.
3. Add a regression test for behavior changes.
4. Update public documentation when behavior, setup, permissions, persistence,
   or platform support changes.
5. Run the verification suite.
6. Exercise the relevant real platform when changing notifications,
   background work, lifecycle behavior, signing, or packaging.

## Verification

Run all checks from the repository root:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test tool
dart run tool/check_code_rules.dart
flutter analyze
flutter test
```

Use [BUILD.md](BUILD.md) for release commands and platform-specific smoke tests.
Emulators do not reproduce every notification permission, sleep/resume path,
desktop environment, or Android battery policy.

For a visible change, regenerate the relevant native screenshots before opening
a pull request:

```bash
./tool/capture_repository_screenshots.sh macos
ANDROID_DEVICE_ID=<emulator-id> ./tool/capture_repository_screenshots.sh android
ANDROID_DEVICE_ID=<emulator-id> ./tool/capture_feature_walkthrough.sh android
```

The visual harness contains only sanitized `example.com` fixtures. Do not
replace them with personal monitor data. CI compares all four generated images
with `docs/screenshots/`, reports stale screenshots as a failed check, and
uploads the freshly recorded walkthrough as a short-lived artifact.

## Pull requests

A pull request should:

- explain the user-visible outcome and why the change is needed;
- identify affected platforms;
- list automated and manual verification performed;
- describe notification, background-work, privacy, persistence, and migration
  implications, or explicitly state that there are none;
- include sanitized screenshots for visible UI changes; and
- avoid unrelated formatting, refactors, dependency upgrades, or generated
  build artifacts.

By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
