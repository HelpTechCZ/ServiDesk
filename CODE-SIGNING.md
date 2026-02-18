# Code Signing Policy

ServiDesk Windows binaries are signed using a certificate provided by [SignPath Foundation](https://signpath.org/).

## Roles

| Role | Person | GitHub |
|------|--------|--------|
| Author | Pavel Račák | [@HelpTechCZ](https://github.com/HelpTechCZ) |
| Reviewer | Pavel Račák | [@HelpTechCZ](https://github.com/HelpTechCZ) |
| Approver | Pavel Račák | [@HelpTechCZ](https://github.com/HelpTechCZ) |

- **Author** – commits code to the repository
- **Reviewer** – reviews and approves pull requests
- **Approver** – approves release builds for code signing

## Build & Signing Process

1. All releases are built via GitHub Actions from the `main` branch
2. Build artifacts are submitted to SignPath for signing
3. Signed binaries are attached to GitHub Releases

No binaries are signed locally. The signing key is stored on SignPath's HSM (Hardware Security Module).

## Privacy

ServiDesk does not collect telemetry or personal data. The agent sends only:
- A unique agent ID (auto-generated UUID)
- Device hostname and OS version
- Hardware info (CPU, RAM, disks) for identification in the admin panel

All remote session data is end-to-end encrypted (ECDH + AES-256-GCM). The relay server cannot read screen content or transferred files.

## Credits

Code signing certificate provided by [SignPath Foundation](https://signpath.org/) via [SignPath.io](https://signpath.io/).
