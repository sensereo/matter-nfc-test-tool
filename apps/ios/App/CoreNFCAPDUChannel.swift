@preconcurrency import CoreNFC
import Foundation

/// One channel per connected tag/session. No raw APDU or response logging.
@MainActor
final class CoreNFCAPDUChannel: APDUChannel {
    private let tag: NFCISO7816Tag
    private let commandTimeout: TimeInterval
    private var closed = false
    private var pending: (UUID, CheckedContinuation<APDUResponse, Error>)?
    private var deadline: DispatchWorkItem?
    private var sequence = 0
    private var sentAt: TimeInterval = 0
    private(set) var diagnosticLines: [String] = []

    init(tag: NFCISO7816Tag, commandTimeout: TimeInterval = 10) {
        self.tag = tag
        self.commandTimeout = commandTimeout
    }

    func transceive(_ bytes: Data) async throws -> APDUResponse {
        try Task.checkCancellation()
        guard !closed else { throw NTLExchangeError.closed }
        guard pending == nil else { throw NTLExchangeError.busy }
        guard let command = NFCISO7816APDU(data: bytes) else { throw NTLExchangeError.invalidCommand }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = (id, continuation)
                sequence += 1
                sentAt = ProcessInfo.processInfo.systemUptime
                let kind: String
                switch command.instructionCode {
                case 0xa4: kind = "SELECT"
                case 0x20: kind = command.instructionClass == 0x90 ? "TRANSPORT_CHAIN" : "TRANSPORT_FINAL"
                case 0xc0: kind = "GET_RESPONSE"
                default: kind = "OTHER"
                }
                record("APDU \(sequence) \(kind) tx=\(command.data?.count ?? 0) expectedRx=\(command.expectedResponseLength)")
                let timer = DispatchWorkItem { [weak self] in
                    self?.complete(id, .failure(NTLExchangeError.timedOut))
                }
                deadline = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + commandTimeout, execute: timer)
                tag.sendCommand(apdu: command) { [weak self] data, sw1, sw2, error in
                    DispatchQueue.main.async {
                        if let error {
                            self?.complete(id, .failure(NTLExchangeError.readerError((error as NSError).code)))
                        } else {
                            self?.complete(id, .success(APDUResponse(data: data, sw1: sw1, sw2: sw2)))
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(id, .failure(CancellationError())) }
        }
    }

    func invalidate() {
        closed = true
        if let (id, _) = pending { complete(id, .failure(NTLExchangeError.closed)) }
    }

    private func complete(_ id: UUID, _ result: Result<APDUResponse, Error>) {
        guard let (activeID, continuation) = pending, activeID == id else { return }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - sentAt) * 1000)
        switch result {
        case .success(let response):
            record("APDU \(sequence) rx=\(response.data.count) sw=\(String(format: "%04X", response.statusWord)) elapsedMs=\(elapsed)")
        case .failure(let error):
            let code = (error as? NTLExchangeError).map { String(describing: $0) } ?? "cancelledOrUnknown"
            record("APDU \(sequence) error=\(code) elapsedMs=\(elapsed)")
        }
        pending = nil
        deadline?.cancel()
        deadline = nil
        if case .failure = result { closed = true }
        continuation.resume(with: result)
    }

    private func record(_ line: String) {
        diagnosticLines.append(line)
        if diagnosticLines.count > 48 { diagnosticLines.removeFirst(diagnosticLines.count - 48) }
    }
}
