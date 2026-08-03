# Changelog

Notable user-visible changes are recorded here. SiteSignal follows
[Semantic Versioning](https://semver.org/).

## Unreleased

## 1.0.1 - 2026-08-03

### Added

- Automatic discovery for ASP.NET live and ready checks, Quarkus aggregate
  health, and Prometheus health and readiness endpoints.
- A non-blocking daily check for the latest stable GitHub release, a manual
  check in Settings, and a visible recommendation when an update is available.

### Security

- Health-check redirects are followed only when they remain on the configured
  website's exact HTTP or HTTPS origin.

## 1.0.0 - 2026-08-03

### Added

- Local-first website monitoring for Android, macOS, Linux, and Windows.
- Same-origin health-path discovery, connectivity-aware checks, response-time
  details, uptime, and bounded transition history.
- Native outage and recovery notifications with four bundled sounds, the system
  sound, silent mode, selection previews, and test alerts.
- Desktop tray operation and Android foreground monitoring.
- Local SQLite persistence, responsive navigation, appearance controls, and
  reproducible light-mode screenshot collections.
- ARM and x86 release packages, SHA-256 checksums, reusable quality checks, and
  a stable tag-driven GitHub release workflow.
- MIT license, contribution guidance, security policy, privacy documentation,
  and architecture notes.

### Fixed

- Test notifications now use the selected delivery sound instead of silently
  posting and playing an unrelated preview.
- Starting another preview stops an active Android system ringtone.
- Website discovery includes `/livez` and rejects cross-origin favicon links.
- Coalesced background checks preserve forced connectivity rechecks.

### Changed

- CI verifies three current light-mode screenshots on macOS and Android without
  creating bot commits.
- Release creation excludes unsupported targets and publishes only the 11
  documented packages plus `SHA256SUMS.txt`.
