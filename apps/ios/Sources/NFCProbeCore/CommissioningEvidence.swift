/// Success requires independent protocol, storage and operational-read evidence.
/// Reopening a saved device is deliberately a different operation from commissioning.
public enum CommissioningEvidence {
    public static func permitsSuccess(existingDevice: Bool, nfcVerified: Bool,
                                      attestationPassed: Bool, commissioningCompleted: Bool,
                                      ipReadMatched: Bool, storageHealthy: Bool) -> Bool {
        guard storageHealthy, ipReadMatched else { return false }
        return existingDevice || (nfcVerified && attestationPassed && commissioningCompleted)
    }
}
