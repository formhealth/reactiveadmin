# Security policy

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**.

Include what you found, the version or commit, and steps to reproduce it. We aim to acknowledge a report within a few days and to agree on a fix and disclosure timeline with you.

## Supported versions

reactiveadmin is early (0.1.0). Only the latest release on the default branch gets security fixes.

## Scope

The gem serves your ActiveAdmin resources through an API, so a report is in scope when it lets someone read or change data that ActiveAdmin's authentication, authorization or the gem's guards should have refused. See the [security guide](docs/guide/security.md) for what the gem enforces and what your app must still do.
