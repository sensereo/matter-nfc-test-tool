import Foundation

/// SELECT command from the pinned Nordic NFCTag implementation (Apache-2.0).
/// See the repository-root THIRD_PARTY_NOTICES.md.
public enum MatterApplicationProbe {
    public static let selectAPDU = Data([
        0x00, 0xA4, 0x04, 0x0C, 0x09,
        0xA0, 0x00, 0x00, 0x09, 0x09, 0x8A, 0x77, 0xE4, 0x01, 0x00
    ])
}
