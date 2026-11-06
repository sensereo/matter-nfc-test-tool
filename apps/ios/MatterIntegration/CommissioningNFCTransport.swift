@preconcurrency import CoreNFC
import Matter
import Foundation

/// Build only with the custom Matter.framework containing MNTNFCReaderBridge.
/// A successful discovery keeps the NFC session open for subsequent Matter messages.
@MainActor
final class CommissioningNFCTransport: NSObject, @preconcurrency MNTNFCTransport,
                                       @preconcurrency NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var channel: CoreNFCAPDUChannel?
    private var exchange: NTLExchange?
    private var generation = UUID()
    private var expected: UInt16 = 0
    private var discovering: ((NSNumber?, Error?) -> Void)?
    private var sending: ((Data?, Error?) -> Void)?
    private var operation: Task<Void, Never>?
    private var deadline: DispatchWorkItem?
    private var connecting = false
    private(set) var applicationSelected = false
    private(set) var completedExchanges = 0
    private(set) var attemptedExchanges = 0
    private(set) var failureCode = "none"
    var onFailure: ((Error) -> Void)?
    var onApplicationSelected: (() -> Void)?
    private let createdUptime = ProcessInfo.processInfo.systemUptime
    private(set) var stageEvents: [String] = []
    private var savedDiagnostics: [String] = []
    var diagnosticLines: [String] { channel?.diagnosticLines ?? savedDiagnostics }

    func recordBridgeEvent(_ event: String) {
        // Bridge supplies fixed stage names only; this is not an SDK logging callback.
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - createdUptime) * 1000)
        stageEvents.append("+\(elapsed)ms \(event)")
        if stageEvents.count > 64 { stageEvents.removeFirst(stageEvents.count - 64) }
    }

    func discoveryStopped() {
        recordBridgeEvent("discovery.stopped_before_selection")
        // The Matter queue is authoritative: SELECT may complete on the main queue
        // just before this notification arrives, but its discovery result is stale.
        guard session != nil else { return }
        close(error: NTLExchangeError.discoveryStopped)
    }

    func discoverTag(withDiscriminator discriminator: UInt16,
                     completion: @escaping (NSNumber?, Error?) -> Void) {
        guard NFCSessionMonitor.shared.canStart else {
            completion(nil, NTLExchangeError.busy)
            return
        }
        invalidate()
        applicationSelected = false
        completedExchanges = 0
        attemptedExchanges = 0
        failureCode = "none"
        savedDiagnostics = []
        guard NFCTagReaderSession.readingAvailable else {
            completion(nil, NTLExchangeError.closed)
            return
        }
        expected = discriminator
        discovering = completion
        let token = generation
        guard let reader = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main),
              NFCSessionMonitor.shared.begin(reader, owner: self) else {
            discovering = nil
            completion(nil, NTLExchangeError.closed)
            return
        }
        session = reader
        recordBridgeEvent("reader.begin")
        reader.alertMessage = "Hold the top of the iPhone near the board's NFC antenna."
        let timer = DispatchWorkItem { [weak self] in
            guard self?.generation == token else { return }
            self?.close(error: NTLExchangeError.timedOut)
        }
        deadline = timer
        // Experimental budget; Core NFC may independently end its session earlier.
        DispatchQueue.main.asyncAfter(deadline: .now() + 55, execute: timer)
        reader.begin()
    }

    func exchangeMessage(_ message: Data, completion: @escaping (Data?, Error?) -> Void) {
        guard let exchange, session != nil else { completion(nil, NTLExchangeError.closed); return }
        guard sending == nil else { completion(nil, NTLExchangeError.busy); return }
        let token = generation
        sending = completion
        attemptedExchanges += 1
        recordBridgeEvent("ntl.exchange.started")
        operation = Task { [weak self] in
            do {
                let response = try await exchange.exchange(message)
                guard let self, self.generation == token else { return }
                let callback = self.sending
                self.sending = nil
                self.operation = nil
                self.completedExchanges += 1
                self.recordBridgeEvent("ntl.exchange.completed")
                callback?(response, nil)
            } catch {
                guard let self, self.generation == token else { return }
                self.close(error: error)
            }
        }
    }

    func invalidate() { close(error: NTLExchangeError.closed, notifyFailure: false) }

    private func close(error: Error, notifyFailure: Bool = true, alreadyInvalidated: Bool = false) {
        let hadSession = session != nil
        if hadSession, notifyFailure, failureCode == "none" {
            if let known = error as? NTLExchangeError {
                failureCode = String(describing: known)
            } else if let known = error as? MatterApplicationIdentity.ParseError {
                failureCode = String(describing: known)
            } else {
                // Numeric code only: localized descriptions may contain device data.
                failureCode = "nfcError(\((error as NSError).code))"
            }
        }
        generation = UUID()
        deadline?.cancel()
        deadline = nil
        operation?.cancel()
        operation = nil
        exchange?.invalidate()
        exchange = nil
        channel?.invalidate()
        if let channel { savedDiagnostics = channel.diagnosticLines }
        channel = nil
        let reader = session
        session = nil
        connecting = false
        let discoveryCallback = discovering
        let sendCallback = sending
        discovering = nil
        sending = nil
        if let reader, !alreadyInvalidated {
            NFCSessionMonitor.shared.requestEnd(reader)
            reader.invalidate()
        }
        discoveryCallback?(nil, error)
        sendCallback?(nil, error)
        // Notify after pending bridge callbacks have been queued onto the Matter queue.
        // Normal teardown must never turn a success/cancellation into a transport failure.
        if hadSession, notifyFailure { onFailure?(error) }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        if self.session === session { recordBridgeEvent("reader.active") }
        NFCSessionMonitor.shared.becameActive(session)
    }

    func tagReaderSession(_ reader: NFCTagReaderSession, didInvalidateWithError error: Error) {
        NFCSessionMonitor.shared.didEnd(reader)
        guard session === reader else { return }
        recordBridgeEvent("reader.invalidated")
        close(error: NTLExchangeError.readerError((error as NSError).code), alreadyInvalidated: true)
    }

    func tagReaderSession(_ reader: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard session === reader, !connecting, discovering != nil else { return }
        recordBridgeEvent("reader.tags_detected count=\(tags.count)")
        guard tags.count == 1, case .iso7816(let tag) = tags[0] else {
            reader.alertMessage = "Hold only one Matter NFC test board near the phone."
            reader.restartPolling()
            return
        }
        connecting = true
        recordBridgeEvent("tag.connect.started")
        let token = generation
        channel = CoreNFCAPDUChannel(tag: tag)
        reader.connect(to: tags[0]) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.recordBridgeEvent(error == nil ? "tag.connect.completed" : "tag.connect.failed")
                guard error == nil, let channel = self.channel else {
                    self.close(error: error.map { NTLExchangeError.readerError(($0 as NSError).code) } ?? .communicationFailed)
                    return
                }
                self.operation = Task { [weak self] in
                    do {
                        let response = try await channel.transceive(MatterApplicationProbe.selectAPDU)
                        let identity = try MatterApplicationIdentity(response: response)
                        guard let self, self.generation == token else { return }
                        guard identity.discriminator == self.expected else {
                            self.close(error: NTLExchangeError.rejected(0x6a80))
                            return
                        }
                        self.exchange = try NTLExchange(channel: channel)
                        self.applicationSelected = true
                        self.recordBridgeEvent("application.selected")
                        self.onApplicationSelected?()
                        self.operation = nil
                        let callback = self.discovering
                        self.discovering = nil
                        self.recordBridgeEvent(callback == nil ? "discovery.callback.missing" : "discovery.callback.invoked")
                        self.session?.alertMessage = "Matter NFC connected. Keep the phone near the antenna until the secure session completes."
                        callback?(NSNumber(value: identity.discriminator), nil)
                    } catch {
                        guard let self, self.generation == token else { return }
                        self.close(error: error)
                    }
                }
            }
        }
    }
}
