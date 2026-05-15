# Security Policy

## Supported Versions

AR-Runner is in pre-v0.1 development. There are no released versions to support.
Once v0.1 ships, the latest tagged release will be the only supported version.

## Reporting a Vulnerability

Please report security vulnerabilities **privately** via GitHub's Private
Vulnerability Reporting:

<https://github.com/jkrilov/AR-Runner/security/advisories/new>

Do **not** open a public issue for security-sensitive findings.

(Note: the link above is fully functional once the repository is public and
Private Vulnerability Reporting is enabled in repo settings.)

Expected response time: best-effort, typically within 7 days. AR-Runner is a
personal hobby project pre-v0.1, not a commercial product — there is no SLA.
Please calibrate expectations accordingly.

## Scope

In scope:

- AR-Runner watch, phone, widget, and core targets.
- The Squad orchestration files in `.squad/` to the extent they could be
  weaponized (e.g., agent prompt injection that could affect future
  contributors using Squad).

Out of scope:

- Apple platform vulnerabilities — report to Apple.
- ActiveLook firmware/SDK vulnerabilities — report to ActiveLook.
- The upstream Squad project — report to <https://github.com/bradygaster/squad>.
