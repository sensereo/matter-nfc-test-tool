# Matter NFC Test Tool for iOS

An experimental SwiftUI app for standalone NFC commissioning and IP verification.
It uses Core NFC and a custom framework built from a pinned Nordic Matter fork.

Status as of 2026-11-06: experimental. Hardware validation, TestFlight
distribution, and independent-user acceptance are pending.

## Start here

1. Read [requirements and building](docs/guides/building.md).
2. Follow the [commissioning guide](docs/guides/commissioning.md).
3. Review [limitations](docs/reference/limitations.md).

Run offline checks from this directory:

```sh
bash scripts/check.sh
```

The Swift package contains testable protocol and recovery logic. The generated
Xcode app also compiles that source directly; do not add the same Swift package
as another linked copy of these types.

See the [documentation index](docs/README.md), [project README](../../README.md),
and [third-party notices](../../THIRD_PARTY_NOTICES.md).
