# Project overview

Verified on 2026-11-06 against the current iOS source.

Matter NFC Test Tool helps developers exercise NFC commissioning on dedicated
Matter-over-Thread experimental boards. The current code targets iOS; there is
no Android implementation or promised Android delivery date.

Platform-specific application code, tests, scripts, and documentation live under
`apps/ios/`. Repository-wide policies and licensing remain at the root.

The first version focuses on NFC commissioning, operational IP ProductID reads,
one persistent tool Fabric, and diagnostic reports. It does not require a cloud
account or Home Assistant. NFC setup-payload acquisition is not implemented:
the user must supply the complete `MT:` payload manually.

Hardware validation and external-user acceptance are pending. See the
[iOS limitations](../apps/ios/docs/reference/limitations.md) for remaining work.
