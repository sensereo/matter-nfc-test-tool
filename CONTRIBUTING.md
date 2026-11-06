# Contributing

Thank you for contributing to Matter NFC Test Tool.

## Before you start

The repository contains an experimental iOS implementation. Read the
[iOS build guide](apps/ios/docs/guides/building.md) and run
`bash scripts/check.sh` from `apps/ios/` for offline checks. Discuss substantial
implementation or dependency changes in an issue before beginning work.

Use English for repository content, code, comments, UI text, issues, pull
requests, and commit messages.

## Reporting bugs and proposing features

Use the issue templates. Describe the expected result, actual result, and steps
to reproduce. For device-related reports, include the app revision, phone model,
OS version, device firmware, and relevant hardware where available.

Use synthetic or redacted examples. Remove access tokens, setup passcodes,
Thread datasets, Wi-Fi passwords, private keys, and identifying device details
from logs and screenshots. Follow [SECURITY.md](SECURITY.md) for vulnerabilities.

## Pull requests

1. Fork the repository and create a focused branch.
2. Make the smallest coherent change and update relevant documentation.
3. Run applicable checks. For documentation, check links and formatting. For
   code changes, include the documented build and test results, and state
   whether hardware validation was performed.
4. Open a pull request describing the problem, change, and validation evidence.

Write concise English commit titles and bodies that describe what changed and
why. Do not include AI co-author trailers or generated-by footers in commits or
pull requests.

Keep local experiments under `.scratch/`. Do not commit generated build output,
credentials, signing assets, or private project material.

## Licensing

Submit only material you have the right to contribute under the project's
[MIT License](LICENSE). Preserve the original license and attribution for any
third-party material and document its source and version when adding it.

## Community

All participation is subject to the [code of conduct](CODE_OF_CONDUCT.md).
