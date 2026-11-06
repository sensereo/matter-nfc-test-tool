# Commissioning and recovery

Verified on 2026-11-06 against the current UI and controller.

## Prepare

Use a dedicated Nordic DK with NFC commissioning firmware and its NFC antenna.
Record the exact board, firmware revision/configuration, phone/iOS, and Thread
border-router version before testing. Ordinary NDEF tags are not substitutes.

Prepare a Thread network whose operational IPv6 devices are reachable from the
phone. The app does not provision the border router or validate routing in advance.
Obtain the board's complete `MT:` payload and that network's Active Operational
Dataset. Neither value should be included in public bug reports.

## Run

1. Enter the full setup payload and hexadecimal dataset. A structurally invalid
   dataset is rejected before commissioning; valid structure does not prove reachability.
2. Confirm that this is a dedicated board using the FFF1 test attestation root.
3. Start commissioning and hold the top of the iPhone near the NFC antenna until
   the app says it can be moved away.
4. Wait for ProductID verification over IP. Initial success requires NFC PASE,
   successful attestation, commissioning completion, a matching operational IP
   read, and successful credential storage.
5. Expand and share the diagnostic report before leaving the app or replacing it.

ProductID is compared with the setup payload, not a separately configured firmware
baseline. The first release does not read setup credentials from NFC.

Input fields are cleared after submission and when the app backgrounds. No dataset
is prefilled into the build. The app does not create a cloud account or upload reports;
the user chooses whether to share a report through the system share sheet.

## Re-verify or recover

- Reopen the app and select **Re-verify current device over IP** to use the saved
  Fabric. This does not claim that a previously interrupted commissioning succeeded.
- Cancellation/backgrounding stops local work; already-applied device changes may
  remain. Inspect the report and device before starting another attempt.
- **Prepare retry before commissioning** is available only for a reservation known
  not to have crossed the commissioning boundary. It preserves the tool Fabric.
- For a new test after actual commissioning, follow the exact board firmware's
  factory-reset procedure, then confirm **Clear reference after board factory reset**.
  This removes only the local reference, not the device's credentials or tool Fabric.
- If credentials are lost, factory-reset the dedicated board before using a new app
  identity. Do not reset a board serving another purpose.

A normal reset/reboot is not a factory reset. Use the factory-reset procedure
for your specific board and firmware; button sequences vary.
