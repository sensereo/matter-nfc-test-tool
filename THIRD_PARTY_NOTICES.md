# Third-party notices

## Nordic / Project CHIP adaptation

The NTL wire behavior in `apps/ios/Sources/NFCProbeCore/NTLExchange.swift` and the
SELECT command in `MatterApplicationProbe.swift` are adapted from Nordic's fork
of Project CHIP, revision `d92ebd4a7766806ad891957dc23ab7850f93e4d4`:

- `src/nfc/NFCTag.cpp`
- `src/nfc/NFCTag.h`

Copyright (c) 2025 Project CHIP Authors.
Licensed under the Apache License, Version 2.0. See [Apache-2.0](licenses/Apache-2.0.txt).
The Swift adaptation uses asynchronous transport and adds bounded messages,
response-chain limits, cancellation, and stricter error handling. It is not a
copy of the full commissioner and does not claim protocol certification.

## Custom Matter framework

The iOS app builds and embeds a custom framework from
[nrfconnect/sdk-connectedhomeip](https://github.com/nrfconnect/sdk-connectedhomeip)
at the pinned revision above. The Objective-C++ reader bridge is compiled inside
that framework because it relies on internal C++/Darwin interfaces. Upstream and
its linked dependencies retain their original licenses and notices.

Build scripts also copy the public test certificate
`credentials/test/attestation/Chip-Test-PAA-FFF1-Cert.der` from the pinned SDK.
No corresponding private key is copied. This is an experimental trust anchor,
not a production device trust store. The upstream certificate remains subject
to its Apache-2.0 license.

This repository does not distribute a prebuilt framework or app. Before binary
redistribution, collect and ship all applicable SDK and linked dependency
licenses/notices. This document alone is not a complete binary notice bundle.
The root MIT license does not replace third-party license terms.
