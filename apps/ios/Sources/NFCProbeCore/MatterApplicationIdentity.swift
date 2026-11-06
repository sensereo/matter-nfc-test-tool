import Foundation

/// Pinned Nordic NTL v1 SELECT response. Never persist discriminator or raw bytes.
public struct MatterApplicationIdentity: Equatable, Sendable {
    public let discriminator: UInt16
    public let vendorID: UInt16
    public let productID: UInt16

    public enum ParseError: Error, Equatable {
        case rejected(UInt16), invalidLength, unsupportedVersion, unsupportedFormat
    }

    public init(response: APDUResponse) throws {
        guard response.statusWord == 0x9000 else { throw ParseError.rejected(response.statusWord) }
        guard response.data.count == 8 else { throw ParseError.invalidLength }
        let bytes = [UInt8](response.data)
        guard bytes[0] == 1 else { throw ParseError.unsupportedVersion }
        guard bytes[1] == 0, bytes[2] & 0xf0 == 0 else { throw ParseError.unsupportedFormat }
        discriminator = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        vendorID = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        productID = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
    }
}
