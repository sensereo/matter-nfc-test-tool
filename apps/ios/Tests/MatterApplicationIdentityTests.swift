import XCTest
@testable import NFCProbeCore

final class MatterApplicationIdentityTests: XCTestCase {
    func testPinnedNordicResponseAndZeroDiscriminator() throws {
        let identity = try MatterApplicationIdentity(response: APDUResponse(
            data: Data([1, 0, 0x0f, 0, 0xff, 0xf1, 0x80, 0x0d]), sw1: 0x90, sw2: 0))
        XCTAssertEqual(identity.discriminator, 3840)
        XCTAssertEqual(identity.vendorID, 65521)
        XCTAssertEqual(identity.productID, 32781)
        XCTAssertEqual(try MatterApplicationIdentity(response: APDUResponse(
            data: Data([1, 0, 0, 0, 0, 0, 0, 0]), sw1: 0x90, sw2: 0)).discriminator, 0)
    }

    func testRejectsUnrecognizedLayoutsBeforeCommissioning() {
        for (bytes, error) in [
            ([UInt8](repeating: 0, count: 7), MatterApplicationIdentity.ParseError.invalidLength),
            ([UInt8](repeating: 0, count: 9), .invalidLength),
            ([2, 0, 0, 0, 0, 0, 0, 0], .unsupportedVersion),
            ([1, 1, 0, 0, 0, 0, 0, 0], .unsupportedFormat),
            ([1, 0, 0x10, 0, 0, 0, 0, 0], .unsupportedFormat)
        ] {
            XCTAssertThrowsError(try MatterApplicationIdentity(response: APDUResponse(data: Data(bytes), sw1: 0x90, sw2: 0))) {
                XCTAssertEqual($0 as? MatterApplicationIdentity.ParseError, error)
            }
        }
    }
}
