# Security Policy

MDMacFanKit installs a helper that runs as root, so security reports are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through GitHub:
**Security → Report a vulnerability** on this repository
([direct link](https://github.com/amd1292/MDMacFanKit/security/advisories/new)).

Include what an attacker could do, the steps to reproduce, and the macOS version and Mac model. You should get a first answer within a week.

## Scope

In scope:

- the root helper (`Sources/MDFanHelper`) and its XPC interface;
- the install and uninstall scripts (`scripts/`);
- anything that lets a process gain privileges or write to the SMC beyond fan targets clamped to hardware limits.

Known limitation, not a vulnerability: the app and helper are signed ad hoc, so the helper cannot check the code signature of the process connecting to it. Any local process can ask it to change fan speeds within the fans' own limits. This is documented in the README.

## Supported versions

Only the latest commit on `main` receives fixes.
