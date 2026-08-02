# Changelog

Notable user-visible changes to SiteSignal are recorded here. The project uses
[Semantic Versioning](https://semver.org/) for releases.

## Unreleased

### Added

- Initial public-release documentation and GitHub contribution templates.
- Cross-platform local website monitoring for macOS, Linux, Windows, Android,
  and iOS.
- Same-origin health-probe discovery, connectivity-aware outage detection, and
  transition-only history.
- Native outage and recovery notifications with selectable sounds.
- Desktop tray operation, Android foreground monitoring, and best-effort iOS
  background refresh.
- Local SQLite persistence, responsive navigation, appearance controls, and
  architecture-specific release packaging.
- Native-engine light/dark screenshots for macOS and Android, refreshed on the
  default branch and verified in pull requests.
- A reproducible, full-feature Android walkthrough recorded at native device
  resolution with status and navigation bars.
- Cost-conscious GitHub Actions CI, full native release builds, checksums,
  prerelease publishing, and monthly dependency updates.

### Changed

- Disabled iOS artifact creation in local build automation, CI, and tagged
  releases while retaining the platform source for future work.
