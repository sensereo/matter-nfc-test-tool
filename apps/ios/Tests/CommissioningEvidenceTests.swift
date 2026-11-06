import XCTest
@testable import NFCProbeCore

final class CommissioningEvidenceTests: XCTestCase {
    func testNewCommissioningRequiresEveryPieceOfEvidence() {
        for mask in 0..<32 {
            XCTAssertEqual(CommissioningEvidence.permitsSuccess(existingDevice: false,
                nfcVerified: mask & 1 != 0, attestationPassed: mask & 2 != 0,
                commissioningCompleted: mask & 4 != 0, ipReadMatched: mask & 8 != 0,
                storageHealthy: mask & 16 != 0), mask == 31)
        }
    }
    func testExistingDeviceReadDoesNotClaimFreshCommissioning() {
        XCTAssertTrue(CommissioningEvidence.permitsSuccess(existingDevice: true, nfcVerified: false,
            attestationPassed: false, commissioningCompleted: false, ipReadMatched: true, storageHealthy: true))
        XCTAssertFalse(CommissioningEvidence.permitsSuccess(existingDevice: true, nfcVerified: false,
            attestationPassed: false, commissioningCompleted: false, ipReadMatched: false, storageHealthy: true))
        XCTAssertFalse(CommissioningEvidence.permitsSuccess(existingDevice: true, nfcVerified: false,
            attestationPassed: false, commissioningCompleted: false, ipReadMatched: true, storageHealthy: false))
    }
}
