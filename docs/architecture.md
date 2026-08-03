# Architecture

SiteSignal is a Flutter application organized by feature. The monitoring
feature uses ports and adapters so business rules can be tested without a
database, network, notification plugin, or desktop window.

## Source layout

- `lib/app/` contains the application shell and top-level navigation.
- `lib/core/` contains small utilities, theme values, and shared widgets.
- `lib/features/monitoring/domain/` contains monitoring entities, policies,
  reducers, and abstract ports.
- `lib/features/monitoring/data/` contains adapters for HTTP, SQLite, native
  notifications and tray integration, and mobile background work.
- `lib/features/monitoring/presentation/` contains the controller, pages, and
  widgets.
- `lib/features/updates/` contains the GitHub release adapter, update state, and
  recommendation UI.
- `lib/main.dart` creates the concrete adapters and starts the application.

The domain layer defines ports such as `HealthChecker`, `MonitorRepository`,
`DesktopBridge`, and `BackgroundMonitor`. The data layer implements them. The
`MonitorController` coordinates those ports and exposes state to the UI.

## Main flows

Application startup:

```text
main -> create adapters -> MonitorController.initialize -> SiteSignalApp
```

Foreground monitoring:

```text
timer or user action -> connectivity check -> website probe
  -> health result reducer -> persist state -> update UI/tray -> notify on change
```

Android background monitoring:

```text
controller -> background configuration snapshot -> foreground-service task
  -> connectivity and website probes -> runtime snapshot -> controller merge
```

Update discovery:

```text
startup, daily resume, or user action -> latest stable GitHub release
  -> semantic version comparison -> recommendation banner -> release page
```

Update discovery never downloads or installs a package. It only opens the
official release page after a user action.

Configuration and runtime results use separate snapshot keys. This keeps a
background result from overwriting a newer pause, site, or settings change.
Desktop monitoring stays in the main process and integrates with the native
window and tray through `DesktopAppBridge`.

## Tests and repository screenshots

The folders intentionally have different jobs:

- `test/` contains fast unit and widget tests. Shared deterministic fakes and
  demo data live in `test/support/`.
- `integration_test/` contains the complete feature flow that runs on a real or
  emulated device.
- `tool/repository_screenshot_main.dart` is an executable fixture, not a test.
  `tool/capture_repository_screenshots.sh` uses it to capture the three light
  mode repository screenshots for macOS and Android.

Keep `test/` and `integration_test/` separate. Flutter discovers and runs them
with different commands, and device tests are slower than unit and widget
tests. Screenshot tooling stays under `tool/` so `flutter test` never discovers
it as a test file.

Integration tests can verify that SiteSignal asks its notification bridge to
play or deliver the selected sound. They cannot reliably assert audio emitted
by the operating system or interact with every native notification dialog.
Android notification-channel sound settings are also user-controlled and
persist outside the app. Native sound behavior therefore needs a short manual
check on a physical device before a release.

## Release flow

The reusable quality workflow formats, analyzes, tests, checks coverage, and
validates repository rules. CI also regenerates the checked-in light mode
screenshots and fails if they changed. Release tags matching `vX.Y.Z` build
Android, macOS, Linux, and Windows packages, then publish one stable GitHub
release with SHA-256 checksums. iOS is not part of the current release matrix.

See [BUILD.md](../BUILD.md) for build commands and release steps.
