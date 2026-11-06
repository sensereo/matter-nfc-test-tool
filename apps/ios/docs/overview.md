# iOS architecture

Verified on 2026-11-06 against the current source.

`CommissioningView` invokes `FullCommissioningController`. The controller opens
one Keychain-backed Matter Fabric, installs `CommissioningNFCTransport`, and
uses the Matter commissioner to establish a PASE session and commission a device.

`CoreNFCAPDUChannel` serializes APDUs with bounded waits. `NTLExchange` implements
message fragmentation and response chaining with size and continuation limits.
`MNTNFCReaderBridge` crosses between the main queue and Matter work queue and
checks the actual secure-session transport before commissioning proceeds.

The Objective-C++ bridge is compiled inside the custom Matter framework because
it uses internal C++/Darwin interfaces. Apple's system Matter framework is not
a substitute. The SDK revision is pinned in `scripts/matter-revision.txt`.

After commissioning, an operational device reads endpoint 0 ProductID. A UDP/TCP
session and matching ProductID are required; a successful NFC SELECT alone is
never sufficient. Initial success also requires verified NFC PASE, attestation,
commissioning completion, and healthy storage.

`CommissioningStore` atomically stores signer material, IPK, SDK state, and
recovery metadata in a device-only Keychain item accessible while unlocked.
The app uses its own Keychain service namespace. Its single current device is reserved before
commissioning, and the possible side-effect boundary is persisted before the SDK
can modify the board. Ambiguous records are retained rather than retried blindly.

The app shuts down the controller/factory and checks final storage writes before
showing completion. Reports are held in memory; saved stage metadata supports
recovery but is not a persistent report archive.
