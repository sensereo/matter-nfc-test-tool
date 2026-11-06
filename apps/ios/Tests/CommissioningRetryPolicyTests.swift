import XCTest
@testable import NFCProbeCore

final class CommissioningRetryPolicyTests: XCTestCase {
    func testInterruptedNewRunBeforeCommissioningCanRetry() {
        for stage in [nil, "establishingNFC", "transportFailed", "cancelled", "timedOut"] as [String?] {
            XCTAssertTrue(CommissioningRetryPolicy.canDiscardReservation(hasCurrentDevice: true,
                boundary: "notStarted", stage: stage, storageHealthy: true))
        }
    }

    func testPersistedCommissioningBoundaryOverridesEarlyLookingOutcome() {
        for boundary in ["mayHaveStarted", "", "unknown"] {
            XCTAssertFalse(CommissioningRetryPolicy.canDiscardReservation(hasCurrentDevice: true,
                boundary: boundary, stage: "transportFailed", storageHealthy: true))
        }
    }

    func testLegacyMigrationOnlyAcceptsUnambiguousPreCommissioningFailure() {
        for stage in [nil, "transportFailed", "establishingNFC", "commissioningFailed", "timedOut", "cancelled", "ipVerified"] as [String?] {
            XCTAssertEqual(CommissioningRetryPolicy.canDiscardReservation(hasCurrentDevice: true,
                boundary: nil, stage: stage, storageHealthy: true), stage == "transportFailed")
        }
    }

    func testMissingDeviceOrFailedStorageNeverAllowsDiscard() {
        for boundary in [nil, "notStarted"] as [String?] {
            XCTAssertFalse(CommissioningRetryPolicy.canDiscardReservation(hasCurrentDevice: false,
                boundary: boundary, stage: "transportFailed", storageHealthy: true))
            XCTAssertFalse(CommissioningRetryPolicy.canDiscardReservation(hasCurrentDevice: true,
                boundary: boundary, stage: "transportFailed", storageHealthy: false))
        }
    }
}
