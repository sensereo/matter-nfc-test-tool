/// Only a pre-commissioning reservation can be discarded without resetting the device.
public enum CommissioningRetryPolicy {
    public static func canDiscardReservation(hasCurrentDevice: Bool, boundary: String?, stage: String?, storageHealthy: Bool) -> Bool {
        guard hasCurrentDevice, storageHealthy else { return false }
        if let boundary { return boundary == "notStarted" }
        // Builds (8)/(9) wrote no boundary. Their transportFailed outcome was only
        // produced before NFC PASE verification and before commissionNode was called.
        // Unknown, interrupted and post-commissioning legacy records stay recoverable.
        return stage == "transportFailed"
    }
}
