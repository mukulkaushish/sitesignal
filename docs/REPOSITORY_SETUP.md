# Publishing SiteSignal on GitHub

This maintainer checklist covers the repository settings that cannot be
committed directly. Complete it before announcing SiteSignal as an open-source
project.

## GitHub About details

Use this repository description:

> Local-first cross-platform website health monitoring with native alerts,
> background checks, tray support, and private on-device history.

Suggested topics:

```text
flutter
dart
website-monitor
uptime-monitor
health-check
local-first
desktop-app
android
macos
linux
windows
notifications
sqlite
```

For the social preview, use a purpose-made image or a sanitized screenshot at
GitHub's recommended size. Never upload a screenshot containing a real private
hostname, monitor URL, notification, or history record.

The committed `pubspec.yaml` uses the public repository URLs:

```yaml
homepage: https://github.com/mukulkaushish/sitesignal
repository: https://github.com/mukulkaushish/sitesignal
issue_tracker: https://github.com/mukulkaushish/sitesignal/issues
```

## Choose a license

A public repository without a license is source-visible, but normal copyright
law does not grant others permission to use, modify, or redistribute the code.
Add a root `LICENSE` file before describing SiteSignal as open source.

Common choices include:

| License | Practical effect |
| --- | --- |
| MIT | Short and permissive; allows commercial and closed-source reuse with attribution and the license notice. |
| Apache-2.0 | Permissive like MIT, with explicit patent-license and patent-termination terms. |
| GPL-3.0 | Copyleft; distributed derivative works generally need to provide corresponding source under GPL-compatible terms. |

Use [Choose a License](https://choosealicense.com/) and
[GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
as starting points, and obtain professional advice when licensing or patent
questions matter. Record the copyright holder and year accurately rather than
copying a placeholder.

After selecting the license:

1. Add the canonical text as `LICENSE` at the repository root.
2. Replace the licensing note in `README.md` with the license name and link.
3. Ensure every bundled icon, sound, code sample, and dependency may be
   redistributed under compatible terms.
4. Decide whether incoming contributions require a Developer Certificate of
   Origin or contributor license agreement. Do not imply either unless it is
   actually enforced.

## Pre-publication review

- Inspect the entire Git history, not only the current files, for credentials,
  signing keys, private URLs, database files, personal information, and large
  generated artifacts.
- Confirm `.gitignore` excludes `.idea`, `.DS_Store`, `local.properties`, build
  output, Flutter ephemeral files, symbols, and signing material.
- Stage files deliberately. Do not use a broad add command until its output has
  been reviewed.
- Remove or sanitize screenshots and example URLs.
- Run a secret scanner against the full history.
- Confirm package identifiers, publisher names, version numbers, and public
  maintainer contact information.
- Review [PRIVACY.md](../PRIVACY.md) against the current implementation.
- Add the selected license and verify GitHub recognizes it.

If a secret ever entered Git history, deleting it from the latest revision is
not enough. Revoke or rotate it first, then rewrite the history before
publishing.

## Recommended repository settings

Enable:

- Issues, using the checked-in bug and feature forms;
- GitHub Actions;
- private vulnerability reporting under **Security**;
- Dependabot alerts and security updates; and
- Discussions if the maintainer wants a separate place for support and design
  questions.

Create the `bug`, `enhancement`, `needs-triage`, `dependencies`, and `ci` labels
referenced by the issue forms and Dependabot configuration. Issues and update
pull requests still open without them, but GitHub cannot apply a label that does
not exist in the repository.

Protect the default branch by requiring pull requests, the **Format, analyze,
and test**, **ARM macOS build and screenshots**, **Android build and
screenshots and walkthrough**, and **Verify committed screenshots** checks,
resolved review conversations, and a current branch before merging. Decide
whether administrator bypass is appropriate for the maintainer model.

Allow GitHub Actions to create commits on `main` so the screenshot refresh job
can write the four generated images. All other CI jobs use read-only repository
permissions; only that job and the tag-triggered prerelease publisher receive
scoped `contents: write` permission. If branch protection forbids all direct
automation pushes, disable the refresh step and require contributors to commit
fresh images instead.

Standard GitHub-hosted runners are free while this repository is public. Do not
switch a workflow to a paid larger-runner label. Keep repository Actions
spending at zero, normal artifact retention at seven days, release handoff
artifacts at one day, and dependency caches disabled unless the storage impact
is reviewed first.

Add a private conduct-reporting contact to `CODE_OF_CONDUCT.md` when one is
available. A dedicated project email is preferable to a personal address.

## First public release

1. Move the relevant entries from **Unreleased** in `CHANGELOG.md` into a dated
   version section.
2. Update `version` in `pubspec.yaml` and keep the MSIX version synchronized.
3. Run the format, repository-rule, analyzer, and test commands from
   `CONTRIBUTING.md`.
4. Run **Actions → Release → Run workflow** and review the complete native build
   matrix without publishing a release.
5. Perform the real-device and desktop smoke tests in `BUILD.md`.
6. Sign Android, macOS, and Windows packages with protected production
   credentials. Public macOS distribution also needs notarization. iOS
   distribution is currently disabled.
7. Attach only intended release packages, checksums, release notes, and any
   required source archive. The workflow also attaches the sanitized Android
   walkthrough.
8. Clearly label unsigned, development-signed, or architecture-specific
   artifacts.
9. Create and push a signed `v*` version tag only after the release contents are
   final. The workflow publishes the free CI outputs as a checksummed
   prerelease because they are unsigned, development signed, or ad-hoc signed.

Do not commit signing certificates, keystores, provisioning profiles,
passwords, API tokens, or private keys. Store release credentials in the
platform's protected secret system and keep public CI permissions minimal.
