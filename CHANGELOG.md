# Changelog

Notable user-visible changes to SiteSignal are recorded here. The project uses
[Semantic Versioning](https://semver.org/) for releases.

## Unreleased

### Added

- Initial public-release documentation and GitHub contribution templates.
- Cross-platform local website monitoring for macOS, Linux, Windows, and
  Android.
- Same-origin health-probe discovery, connectivity-aware outage detection, and
  transition-only history.
- Native outage and recovery notifications with selectable sounds.
- Desktop tray operation and Android foreground monitoring.
- Local SQLite persistence, responsive navigation, appearance controls, and
  architecture-specific release packaging.
- Native-engine light-mode screenshots of Overview, History, and Settings for
  macOS and Android, with reproducible captures uploaded as CI review
  artifacts.
- A reproducible Android end-to-end feature flow in CI.
- Cost-conscious GitHub Actions CI, full native release builds, checksums,
  and prerelease publishing.

### Changed

- Disabled iOS artifact creation in local build automation, CI, and tagged
  releases while retaining the platform source for future work.
- Removed bot-authored dependency pull requests and screenshot commits.
