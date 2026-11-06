import Foundation
@preconcurrency import Matter
import SwiftUI

/// The SDK may invoke this delegate on any thread. It never bypasses attestation.
private final class StrictAttestationDelegate: NSObject, MTRDeviceAttestationDelegate {
    var completed: ((Bool, Int?) -> Void)?
    func deviceAttestationCompleted(for controller: MTRDeviceController, opaqueDeviceHandle: UnsafeMutableRawPointer,
                                    attestationDeviceInfo: MTRDeviceAttestationDeviceInfo, error: Error?) {
        completed?(error == nil, error.map { ($0 as NSError).code })
        // The SDK handles rejection when ignoreAttestationFailure is false.
        do { try controller.continueCommissioningDevice(opaqueDeviceHandle, ignoreAttestationFailure: false) }
        catch { completed?(false, (error as NSError).code) }
    }
}

@MainActor
final class FullCommissioningController: NSObject, ObservableObject, @preconcurrency MTRDeviceControllerDelegate {
    enum Operation: String {
        case commissioning = "NFC commissioning"
        case verify = "IP re-verification"
    }
    private var operation = Operation.commissioning

    @Published private(set) var busy = false
    @Published private(set) var message = "Ready to commission a Thread test device over NFC."
    @Published private(set) var report: String?
    @Published private(set) var hasCurrentDevice = false
    @Published private(set) var canRetryBeforeCommissioning = false
    private var controller: MTRDeviceController?
    private var store: CommissioningStore?
    private var transport: CommissioningNFCTransport?
    private var attestationDelegate: StrictAttestationDelegate?
    private var ownsFactory = false
    private var ending = false
    private var runID = UUID()
    private var started = Date()
    private var uptime: TimeInterval = 0
    var startedUptime: TimeInterval { uptime }
    private var timer: DispatchWorkItem?
    private var dataset: Data?
    private var nodeID: NSNumber = 1
    private var expectedPID: UInt16 = 0
    private var nfcVerified = false
    private var commissioned = false
    private var readingExisting = false
    private var attestation = "NOT EXECUTED"
    private var network = "NOT EXECUTED"
    private var ipResult = "NOT EXECUTED"
    private var stage = "ready"
    private var events: [String] = []
    private var lastError = "none"

    func refresh() {
        guard !busy else { return }
        do {
            let storage = try CommissioningStore(openExisting: false)
            updateRecoveryState(storage)
            if canRetryBeforeCommissioning {
                message = "The previous attempt did not start commissioning. Prepare a retry, then restart the test board's NFC interface as instructed by its firmware."
            } else if hasCurrentDevice {
                message = "Saved device state: \(storage.text("stage") ?? "unknown"). Re-verify over IP; an interrupted operation requires checking the device."
            }
        } catch {
            canRetryBeforeCommissioning = false
            message = "Cannot read Fabric storage. Keep the phone unlocked; credentials will not be recreated automatically."
        }
    }

    private func updateRecoveryState(_ storage: CommissioningStore) {
        hasCurrentDevice = storage.text("currentNode") != nil
        canRetryBeforeCommissioning = CommissioningRetryPolicy.canDiscardReservation(
            hasCurrentDevice: hasCurrentDevice, boundary: storage.text("commissioningBoundary"),
            stage: storage.text("stage"), storageHealthy: !storage.hasWriteFailure)
    }

    func prepareRetryBeforeCommissioning() {
        guard !busy, NFCSessionMonitor.shared.canStart,
              !MTRDeviceControllerFactory.sharedInstance().isRunning else { return }
        do {
            let storage = try CommissioningStore(openExisting: true)
            updateRecoveryState(storage)
            guard canRetryBeforeCommissioning else {
                message = "Cannot confirm that commissioning never started. Keep the record and check the device."; return
            }
            try storage.clearCurrent()
            updateRecoveryState(storage)
            message = "The unused device reservation was cleared. The tool Fabric is retained. Restart the board's NFC interface before retrying."
        } catch {
            canRetryBeforeCommissioning = false
            message = "Cannot safely prepare a retry. The Fabric is retained. Keep the phone unlocked and save the report."
        }
    }

    func confirmBoardFactoryReset() {
        guard !busy else { return }
        do {
            let storage = try CommissioningStore(openExisting: true)
            try storage.clearCurrent()
            hasCurrentDevice = false
            canRetryBeforeCommissioning = false
            report = nil
            message = "Local device reference cleared; tool Fabric retained. Confirm the board was factory reset before commissioning again."
        } catch { message = "Failed to clear the local record. The Fabric was not recreated." }
    }

    func start(payloadText: String, datasetText: String) {
        guard !busy, NFCSessionMonitor.shared.canStart else { return }
        report = nil
        let payloadText = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard payloadText.hasPrefix("MT:"), let payload = MTRSetupPayload(payload: payloadText),
              !payload.hasShortDiscriminator, !payload.isConcatenated else {
            message = "Enter the complete MT: setup payload for one test device."; return
        }
        let parsed: Data
        do { parsed = try ThreadDatasetInput.parse(datasetText) }
        catch { message = "Invalid Thread Active Dataset or missing required fields. Paste the complete hexadecimal TLV."; return }
        guard !MTRDeviceControllerFactory.sharedInstance().isRunning else {
            message = "Finish the other Matter operation first."; return
        }
        beginRun(existing: false)
        do {
            try openController(existingOnly: false)
            guard let store, store.text("currentNode") == nil else {
                throw CommissioningStore.Failure.corrupt
            }
            guard let next = UInt64(store.text("nextNode") ?? "1"), next > 0, next < 0xffff_ffef_ffff_ffff else {
                throw CommissioningStore.Failure.corrupt
            }
            nodeID = NSNumber(value: next)
            expectedPID = payload.productID.uint16Value
            // Reserve first: a failed run cannot silently re-use an operational node identity.
            try store.reserve(node: next, productID: expectedPID)
            hasCurrentDevice = true
            canRetryBeforeCommissioning = false
            setStage("establishingNFC")
            guard !store.hasWriteFailure else { throw CommissioningStore.Failure.writeFailed }
            dataset = parsed
            payload.discoveryCapabilities = MTRDiscoveryCapabilities(rawValue: 1 << 4)
            let id = runID
            let reader = CommissioningNFCTransport()
            reader.onApplicationSelected = { [weak self] in
                guard let self, self.runID == id, self.busy, !self.ending else { return }
                self.message = "NFC connected. Establishing a secure session; keep the phone near the antenna."
            }
            reader.onFailure = { [weak self] error in
                guard let self, self.runID == id, self.busy, !self.ending else { return }
                self.event("nfc.closed")
                if !self.nfcVerified {
                    self.lastError = String(describing: error)
                    self.finish("transportFailed", "NFC secure session was not established. Save the report.")
                } else {
                    // Device may stop NFC once it is commissioned. Let the SDK resolve the
                    // pending commissioning/IP transition; never turn RF loss into success.
                    self.message = "NFC ended. Waiting for the Matter stack to resolve commissioning; check the report."
                }
            }
            transport = reader
            MNTNFCReaderBridge.installTransport(reader) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.runID == id, self.busy, !self.ending else { return }
                    guard error == nil, let controller = self.controller else {
                        self.finish("failed", "Cannot initialize NFC transport."); return
                    }
                    do {
                        self.message = "Hold the phone near the antenna until prompted to move it away."
                        try controller.setupCommissioningSession(with: payload, newNodeID: self.nodeID)
                    } catch { self.record(error); self.finish("failed", "Cannot start NFC commissioning.") }
                }
            }
        } catch {
            record(error)
            finish("initializationFailed", "Initialization failed or a device record requires review. Re-verify the device or follow the board recovery instructions.")
        }
    }

    func verifyCurrent() { startExisting(.verify) }
    private func startExisting(_ action: Operation) {
        guard !busy, NFCSessionMonitor.shared.canStart, !MTRDeviceControllerFactory.sharedInstance().isRunning else { return }
        beginRun(existing: true)
        operation = action
        do {
            try openController(existingOnly: true)
            guard let rawNode = store?.text("currentNode"), let node = UInt64(rawNode),
                  let rawPID = store?.text("expectedPID"), let pid = UInt16(rawPID) else { throw CommissioningStore.Failure.corrupt }
            nodeID = NSNumber(value: node)
            expectedPID = pid
            verifyIP()
        } catch { record(error); finish("restoreFailed", "Cannot restore the original Fabric or device record. No replacement Fabric will be created automatically.") }
    }

    private func beginRun(existing: Bool) {
        MTRSetLogCallback(.error, nil)
        busy = true; ending = false; readingExisting = existing
        operation = existing ? .verify : .commissioning
        report = nil; events = []; lastError = "none"
        nfcVerified = false; commissioned = false
        attestation = "NOT EXECUTED"; network = "NOT EXECUTED"; ipResult = "NOT EXECUTED"
        stage = "initializing"; runID = UUID(); started = Date(); uptime = ProcessInfo.processInfo.systemUptime
        let id = runID
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.runID == id, self.busy, !self.ending else { return }
            self.finish("timedOut", "Operation timed out. Device state is unknown; save the report.")
        }
        timer = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + (existing ? 45 : 150), execute: timeout)
    }

    private func openController(existingOnly: Bool) throws {
        let storage = try CommissioningStore(openExisting: existingOnly)
        store = storage
        guard let raw = storage.storageData(forKey: "app.signer"), let ipk = storage.storageData(forKey: "app.ipk") else {
            throw CommissioningStore.Failure.corrupt
        }
        let factory = MTRDeviceControllerFactory.sharedInstance()
        let params = MTRDeviceControllerFactoryParams(storage: storage)
        params.shouldStartServer = false
        guard let url = Bundle.main.url(forResource: "Chip-Test-PAA-FFF1-Cert", withExtension: "der") else {
            throw CommissioningStore.Failure.corrupt
        }
        params.productAttestationAuthorityCertificates = [try Data(contentsOf: url)]
        try factory.start(params)
        ownsFactory = true
        guard let fabrics = factory.knownFabrics, fabrics.count <= 1 else { throw CommissioningStore.Failure.corrupt }
        let startup = MTRDeviceControllerStartupParams(ipk: ipk, fabricID: 1, nocSigner: try FabricSigningKey(raw: raw))
        startup.vendorID = 0xfff1
        if !fabrics.isEmpty {
            controller = try factory.createController(onExistingFabric: startup)
        } else {
            guard !existingOnly, storage.text("fabricCreated") == nil, storage.text("currentNode") == nil else {
                throw CommissioningStore.Failure.corrupt
            }
            controller = try factory.createController(onNewFabric: startup)
        }
        try storage.put("yes", key: "fabricCreated")
        controller?.setDeviceControllerDelegate(self, queue: .main)
        guard !storage.hasWriteFailure else { throw CommissioningStore.Failure.writeFailed }
    }

    func controller(_ controller: MTRDeviceController, commissioningSessionEstablishmentDone error: Error?) {
        guard controller === self.controller, busy, !ending else { return }
        guard error == nil else { record(error!); finish("paseFailed", "NFC secure session was not established."); return }
        let id = runID
        MNTNFCReaderBridge.verifyNFCSession(for: controller, nodeID: nodeID) { [weak self] verified in
            DispatchQueue.main.async {
                guard let self, self.runID == id, self.busy, !self.ending else { return }
                guard verified else { self.finish("unexpectedTransport", "Cannot verify that the secure session used NFC."); return }
                self.nfcVerified = true
                self.setStage("commissioning")
                self.message = "NFC secure session verified. Attesting the device and configuring Thread; keep the phone near the antenna."
                let params = MTRCommissioningParameters()
                params.threadOperationalDataset = self.dataset
                params.failSafeTimeout = 60
                let delegate = StrictAttestationDelegate()
                delegate.completed = { [weak self] passed, code in
                    DispatchQueue.main.async {
                        guard let self, self.runID == id, self.busy, !self.ending else { return }
                        self.attestation = passed ? "PASSED (experimental FFF1 test root)" : "FAILED"
                        self.event(passed ? "attestation.passed" : "attestation.failed")
                        if let code { self.lastError = "attestationError(\(code))" }
                    }
                }
                self.attestationDelegate = delegate
                params.deviceAttestationDelegate = delegate
                self.attestation = "IN PROGRESS"
                self.network = "DATASET PROVIDED TO SDK; SEND NOT CONFIRMED"
                do {
                    // Persist the boundary BEFORE the SDK may mutate the device. A crash
                    // or thrown SDK call after this point must retain recovery information.
                    guard let store = self.store, !store.hasWriteFailure else {
                        throw CommissioningStore.Failure.writeFailed
                    }
                    try store.put("mayHaveStarted", key: "commissioningBoundary")
                    try controller.commissionNode(withID: self.nodeID, commissioningParams: params)
                    self.dataset = nil
                } catch { self.record(error); self.finish("commissioningFailed", "Cannot continue commissioning. Save the report.") }
            }
        }
    }

    func controller(_ controller: MTRDeviceController, commissioneeHasReceivedNetworkCredentials nodeID: NSNumber) {
        guard controller === self.controller, busy, !ending, nodeID == self.nodeID else { return }
        network = "CREDENTIALS SENT; JOIN NOT YET VERIFIED"
        setStage("joiningThread")
        message = "Thread credentials sent. Waiting for network joining and commissioning; keep the phone near the antenna."
    }

    func controller(_ controller: MTRDeviceController, commissioningComplete error: Error?, nodeID: NSNumber?) {
        guard controller === self.controller, busy, !ending else { return }
        guard error == nil, nodeID == self.nodeID else {
            if let error { record(error) }
            finish("commissioningFailed", "Commissioning did not complete. Check the device state and save the report.")
            return
        }
        commissioned = true
        network = "DATASET PROVIDED; COMMISSIONING COMPLETED (radio not independently verified)"
        event("commissioning.completed")
        // Close NFC before reading through an operational device, not the PASE proxy.
        transport?.onFailure = nil
        transport?.invalidate()
        verifyIP()
    }

    private func verifyIP() {
        guard let controller else { finish("failed", "Controller unavailable."); return }
        setStage("verifyingIP")
        message = "You can move the phone away. Reading ProductID over IP."
        ipResult = "IN PROGRESS"
        let device = MTRBaseDevice(nodeID: nodeID, controller: controller)
        guard let cluster = MTRBaseClusterBasicInformation(device: device, endpointID: 0, queue: .main) else {
            ipResult = "FAILED"
            finish("ipVerificationFailed", "Cannot create the IP attribute read request.")
            return
        }
        let id = runID
        cluster.readAttributeProductID { [weak self] value, error in
            DispatchQueue.main.async {
                guard let self, self.runID == id, self.busy, !self.ending else { return }
                guard error == nil, let value else {
                    if let error { self.record(error) }
                    self.ipResult = "FAILED"
                    self.finish("ipVerificationFailed", "IP attribute read failed. Re-verify the current device later.")
                    return
                }
                let type = device.sessionTransportType
                guard type == .UDP || type == .TCP, value == NSNumber(value: self.expectedPID) else {
                    self.ipResult = "MISMATCH (transport or ProductID)"
                    self.finish("ipVerificationFailed", "Attribute or transport did not match expectations. Save the report.")
                    return
                }
                self.ipResult = "PASSED (operational IP session, ProductID=\(value))"
                self.finish(self.readingExisting ? "ipVerified" : "commissionedAndIPVerified",
                            self.readingExisting ? "IP verification passed on the original tool Fabric." : "Tool Fabric commissioning and IP verification passed.")
            }
        }
    }

    func cancel() {
        guard busy, !ending else { return }
        finish("cancelled", "Operation cancelled. Device changes may remain; check its state before recovery.")
    }
    private func record(_ error: Error) { lastError = "error(\((error as NSError).code))" }
    private func event(_ value: String) {
        events.append("+\(Int((ProcessInfo.processInfo.systemUptime - uptime) * 1000))ms \(value)")
        if events.count > 64 { events.removeFirst(events.count - 64) }
    }
    private func setStage(_ value: String) {
        stage = value; event(value)
        try? store?.put(value, key: "stage")
    }
    private func finish(_ outcome: String, _ description: String) {
        guard busy, !ending else { return }
        ending = true; timer?.cancel(); timer = nil; dataset = nil
        let lastStage = stage
        try? store?.put(outcome, key: "stage")
        let storageFailed = store?.hasWriteFailure == true
        let wantsSuccess = ["commissionedAndIPVerified", "ipVerified"].contains(outcome)
        let evidenceComplete = CommissioningEvidence.permitsSuccess(existingDevice: readingExisting,
            nfcVerified: nfcVerified, attestationPassed: attestation.hasPrefix("PASSED"),
            commissioningCompleted: commissioned, ipReadMatched: ipResult.hasPrefix("PASSED"), storageHealthy: !storageFailed)
        let finalOutcome = storageFailed ? "storageFailed" : (wantsSuccess && !evidenceComplete ? "incompleteEvidence" : outcome)
        let finalDescription = storageFailed ? "Credential storage failed. Save the report and check the device state." :
            (wantsSuccess && !evidenceComplete ? "Success evidence is incomplete. Save the report and check the device state." : description)
        report = """
        Matter NFC Test — Experimental full commissioning
        Run: \(runID)
        Started: \(started.ISO8601Format())
        App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"))
        Elapsed ms: \(Int((ProcessInfo.processInfo.systemUptime - uptime) * 1000))
        Outcome: \(finalOutcome)
        Last stage: \(lastStage)
        Operation: \(operation.rawValue)
        Verified PASE transport this run: \(nfcVerified ? "NFC" : "NOT VERIFIED")
        Device attestation: \(attestation)
        Matter commissioning this run: \(commissioned ? "COMPLETED" : "NOT CONFIRMED")
        Thread configuration: \(network)
        IP verification: \(ipResult)
        Storage: \(storageFailed ? "FAILED; credentials require recovery" : "Keychain")
        Commissioning boundary: \(store?.text("commissioningBoundary") ?? "unknown (legacy record)")
        Error: \(lastError)
        NTL completed / attempted: \(transport?.completedExchanges ?? 0) / \(transport?.attemptedExchanges ?? 0)
        NFC result: \(transport?.failureCode ?? "notStarted")
        Stage events:
        \(events.joined(separator: "\n"))
        APDU diagnostics (metadata only):
        \(transport?.diagnosticLines.joined(separator: "\n") ?? "none")
        Transport stage events (relative to transport creation):
        \(transport?.stageEvents.joined(separator: "\n") ?? "none")
        """
        if operation == .commissioning { try? controller?.cancelCommissioning(forNodeID: nodeID) }
        transport?.onFailure = nil
        if ownsFactory, transport != nil {
            MNTNFCReaderBridge.removeTransport { [self] in
                DispatchQueue.main.async { self.cleanup(finalDescription) }
            }
        } else { cleanup(finalDescription) }
    }
    private func cleanup(_ description: String) {
        controller?.shutdown(); controller = nil
        if ownsFactory { MTRDeviceControllerFactory.sharedInstance().stop() }
        let finalStorageFailed = store?.hasWriteFailure == true
        if let store { updateRecoveryState(store) }
        if finalStorageFailed, let saved = report {
            report = saved.replacingOccurrences(of: "Outcome: commissionedAndIPVerified", with: "Outcome: storageFailed")
                .replacingOccurrences(of: "Outcome: ipVerified", with: "Outcome: storageFailed")
                .replacingOccurrences(of: "Storage: Keychain", with: "Storage: FAILED during cleanup")
        }
        ownsFactory = false; transport = nil; attestationDelegate = nil; store = nil
        busy = false; ending = false
        message = finalStorageFailed ? "Credential storage failed during cleanup. Save the report and check the device state." : description
    }
}
