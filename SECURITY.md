# Security policy

## Supported versions

Security fixes are applied to the current default branch and, when releases
exist, the latest release line. Older builds may not receive backports.

| Version | Supported |
| --- | --- |
| Default branch | Yes |
| Latest release | Yes |
| Older releases | Best effort |

## Reporting a vulnerability

Do not open a public issue containing vulnerability details, credentials,
private monitor URLs, database contents, signing material, or exploit steps.

Use GitHub's **Security → Report a vulnerability** flow when private
vulnerability reporting is enabled for the repository. If that option is not
available, open a minimal public issue titled **Security contact request** that
names only the affected component and asks the maintainer for a private
channel. Do not include sensitive technical details in that issue.

A useful private report includes:

- the affected version, commit, and platform;
- the vulnerability class and expected impact;
- minimal reproduction steps or a proof of concept;
- whether user interaction or a particular configuration is required; and
- suggested remediation, if known.

Please allow maintainers time to reproduce and address the issue before public
disclosure. No response-time or bounty commitment is currently offered.

## Security-sensitive areas

Reports are especially useful when they concern URL validation, redirect
handling, credential exposure, notification privacy, local database access,
native platform channels, background execution, release signing, or dependency
supply-chain behavior.

General privacy behavior is documented in [PRIVACY.md](PRIVACY.md).
