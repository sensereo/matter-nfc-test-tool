@preconcurrency import CoreNFC
import SwiftUI

/// Both entry points share the single device NFC reader lifecycle.
@MainActor
final class NFCSessionMonitor: ObservableObject {
    static let shared = NFCSessionMonitor()
    @Published private(set) var lifecycle = NFCSessionLifecycle()
    private var reader: NFCTagReaderSession?
    // Keep the delegate alive after transport/controller teardown until didInvalidate.
    private var owner: AnyObject?
    private var id = UUID()
    var canStart: Bool { lifecycle.canStart }

    func begin(_ reader: NFCTagReaderSession, owner: AnyObject) -> Bool {
        let id = UUID()
        guard lifecycle.begin(id: id) else { return false }
        self.id = id
        self.reader = reader
        self.owner = owner
        return true
    }
    func becameActive(_ reader: NFCTagReaderSession) {
        guard self.reader === reader else { return }
        lifecycle.becameActive(id: id)
    }
    func requestEnd(_ reader: NFCTagReaderSession) {
        guard self.reader === reader else { return }
        lifecycle.requestEnd(id: id)
    }
    func didEnd(_ reader: NFCTagReaderSession) {
        guard self.reader === reader else { return }
        lifecycle.didEnd(id: id)
        self.reader = nil
        owner = nil
    }
}
