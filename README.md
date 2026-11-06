# Matter NFC Test Tool

An experimental developer tool for commissioning a Matter-over-Thread test
device through NFC and verifying it over IP.

## Status

Verified on 2026-11-06 against the iOS source: the repository contains
an independent commissioning app, core tests, and scripts for building a pinned
custom Matter framework. Hardware acceptance is pending. There is
no published installable release or TestFlight build.

The current implementation targets iOS. Android is not implemented.

## Scope

- Manually enter a device's complete `MT:` setup payload and Thread Active Dataset.
- Establish and verify an NFC PASE session, perform test-device attestation, and
  commission into one persistent tool Fabric.
- Read endpoint 0 Basic Information ProductID over operational IP and compare
  it with the supplied setup payload.
- Re-verify the saved device, cancel operations, share diagnostic text, and
  clear the local device reference after a manual board factory reset.

This version trusts the public FFF1 test attestation root only. It is intended
for dedicated experimental boards, not production device commissioning.
Home Assistant integration, temperature reads, multi-admin sharing, and Wi-Fi
commissioning are outside this version's scope.

## Getting started

Start with the [iOS README](apps/ios/README.md) and
[build instructions](apps/ios/docs/guides/building.md).
Read the [known limitations](apps/ios/docs/reference/limitations.md) before testing.

- [Documentation](docs/README.md)
- [Contributing](CONTRIBUTING.md)
- [Code of conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.md)

Repository documentation, code, comments, and UI text use English.

## License

Original project material is provided under the [MIT License](LICENSE).
Third-party adaptations and dependencies retain their applicable licenses;
see [third-party notices](THIRD_PARTY_NOTICES.md).
No certification or endorsement by a standards organization or vendor is claimed.
