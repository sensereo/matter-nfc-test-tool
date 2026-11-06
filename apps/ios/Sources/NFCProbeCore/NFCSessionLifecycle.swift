import Foundation

/// Tracks API lifecycle, not the visibility of the system sheet or physical tag removal.
public struct NFCSessionLifecycle: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, opening, active, closing, ended }
    public private(set) var phase: Phase = .idle
    private var id: UUID?
    public init() {}
    public var canStart: Bool { phase == .idle || phase == .ended }

    @discardableResult
    public mutating func begin(id: UUID) -> Bool {
        guard canStart else { return false }
        self.id = id
        phase = .opening
        return true
    }
    public mutating func becameActive(id: UUID) {
        guard self.id == id, phase == .opening else { return }
        phase = .active
    }
    public mutating func requestEnd(id: UUID) {
        guard self.id == id, phase == .opening || phase == .active else { return }
        phase = .closing
    }
    public mutating func didEnd(id: UUID) {
        guard self.id == id, !canStart else { return }
        phase = .ended
    }
}
