import XCTest
@testable import NFCProbeCore

final class ThreadDatasetInputTests: XCTestCase {
    // Synthetic data only: no network credentials from a real border router.
    private var fields: [(UInt8, [UInt8])] {
        [(0, [0, 0, 15]), (1, [0x12, 0x34]), (2, Array(repeating: 1, count: 8)),
         (3, Array("Lab".utf8)), (4, Array(repeating: 2, count: 16)),
         (5, Array(repeating: 3, count: 16)), (7, [0xfd, 0, 0, 0, 0, 0, 0, 1]),
         (12, [2, 160, 0xf7, 0xf8]), (14, [0, 0, 0, 0, 0, 1, 0, 0]), (53, [0, 4, 0, 0x1f, 0xff, 0xe0])]
    }
    private func hex(_ fields: [(UInt8, [UInt8])]) -> String {
        fields.flatMap { [$0.0, UInt8($0.1.count)] + $0.1 }.map { String(format: "%02x", $0) }.joined()
    }
    func testValidDatasetAndWhitespace() throws {
        let encoded = hex(fields)
        XCTAssertEqual(try ThreadDatasetInput.parse(" \n" + encoded.uppercased() + "\n").count, encoded.count / 2)
    }
    func testMalformedAndDuplicateTLVs() {
        for text in ["", "0", "zz", hex(fields) + "aa", hex(fields) + "aa02ff", hex(fields) + "000300000f"] {
            XCTAssertThrowsError(try ThreadDatasetInput.parse(text))
        }
    }
    func testMissingMandatoryFields() {
        for index in fields.indices {
            var value = fields; value.remove(at: index)
            XCTAssertThrowsError(try ThreadDatasetInput.parse(hex(value)))
        }
    }
    func testInvalidChannelMaskAndPendingDataset() {
        var value = fields
        value[0].1 = [0, 0, 27]
        XCTAssertThrowsError(try ThreadDatasetInput.parse(hex(value)))
        value = fields; value[value.count - 1].1 = [0, 4, 0, 0, 0, 0]
        XCTAssertThrowsError(try ThreadDatasetInput.parse(hex(value)))
        value = fields; value.append((51, Array(repeating: 0, count: 8)))
        XCTAssertThrowsError(try ThreadDatasetInput.parse(hex(value)))
    }
    func testWireMaskSupportsEveryStandardChannelIncluding25() throws {
        // Wire mask 00 1f ff e0 represents channels 11...26 (host mask 07 ff f8 00).
        for channel: UInt8 in 11...26 {
            var value = fields
            value[0].1 = [0, 0, channel]
            XCTAssertNoThrow(try ThreadDatasetInput.parse(hex(value)), "channel \(channel)")
        }
    }
    func testSingleChannelWireMaskRejectsOtherChannels() throws {
        var value = fields
        value[0].1 = [0, 0, 25]
        value[value.count - 1].1 = [0, 4, 0, 0, 0, 0x40]
        XCTAssertNoThrow(try ThreadDatasetInput.parse(hex(value)))
        value[0].1 = [0, 0, 24]
        XCTAssertThrowsError(try ThreadDatasetInput.parse(hex(value)))
    }
}
