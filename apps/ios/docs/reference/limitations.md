# Functional limitations

Verified on 2026-11-06 against the current source.

- Complete `MT:` setup information is entered manually. Obtaining onboarding
  credentials over NFC remains an unresolved requirement, not an implemented feature.
- ProductID is checked against the supplied payload, not an independent firmware recipe.
- Only the public FFF1 test PAA is trusted. This is not a production trust store.
- One current device and one tool Fabric are supported. No multi-device manager,
  HA connection, temperature read, multi-admin sharing, or Wi-Fi commissioning is included.
- Reports are kept in memory. Minimal device/stage metadata persists, but full reports
  do not survive app termination. Share before replacing a report or exiting.
- Reports lack automatic phone-model/iOS and fixed firmware-recipe fields. Add that
  context manually after removing identifying information when reporting a problem.
- Foreground operation is required. Cancelling or backgrounding does not undo board changes.

For build requirements, see [Building](../guides/building.md).
