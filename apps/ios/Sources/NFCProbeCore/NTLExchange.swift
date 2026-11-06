// Protocol adaptation based on Project CHIP Authors (2025), Apache-2.0.
// See the repository-root THIRD_PARTY_NOTICES.md and licenses/Apache-2.0.txt.
import Foundation

/// Wire behavior follows Nordic sdk-connectedhomeip d92ebd4, src/nfc/NFCTag.cpp.
/// This layer exchanges opaque Matter messages; it does not implement commissioning.
public struct APDUResponse: Sendable, Equatable {
    public let data: Data
    public let sw1: UInt8
    public let sw2: UInt8
    public init(data: Data, sw1: UInt8, sw2: UInt8) {
        self.data = data
        self.sw1 = sw1
        self.sw2 = sw2
    }
    public var statusWord: UInt16 { UInt16(sw1) << 8 | UInt16(sw2) }
}

public enum NTLExchangeError: Error, Equatable {
    case busy, closed, timedOut, communicationFailed, invalidCommand
    case invalidMessageLength, invalidLimits, responseTooLarge, tooManyResponseBlocks
    case unexpectedIntermediateData, rejected(UInt16)
    /// Numeric Core NFC error only; never retain localized descriptions or userInfo.
    case readerError(Int)
    case discoveryStopped
}

@MainActor
public protocol APDUChannel: AnyObject {
    /// Implementations must serialize commands and bound callback waits.
    func transceive(_ command: Data) async throws -> APDUResponse
    /// A failed/cancelled exchange cannot safely resume a partially chained message.
    func invalidate()
}

@MainActor
public final class NTLExchange {
    public static let maximumMessageSize = 1280
    private let channel: any APDUChannel
    private let transmitSize: Int
    private let receiveSize: Int
    private var busy = false
    private var closed = false

    /// Upstream uses 256-byte APDU buffers: 6 bytes command overhead, 2 bytes status.
    public init(channel: any APDUChannel, transmitSize: Int = 250, receiveSize: Int = 254) throws {
        guard (1...250).contains(transmitSize), (1...254).contains(receiveSize) else {
            throw NTLExchangeError.invalidLimits
        }
        self.channel = channel
        self.transmitSize = transmitSize
        self.receiveSize = receiveSize
    }

    public func invalidate() {
        closed = true
        channel.invalidate()
    }

    public func exchange(_ message: Data) async throws -> Data {
        guard !closed else { throw NTLExchangeError.closed }
        guard !busy else { throw NTLExchangeError.busy }
        guard (1...Self.maximumMessageSize).contains(message.count) else {
            throw NTLExchangeError.invalidMessageLength
        }
        busy = true
        defer { busy = false }
        do {
            let bytes = [UInt8](message)
            var offset = 0
            var response = APDUResponse(data: Data(), sw1: 0x90, sw2: 0)
            while offset < bytes.count {
                let length = min(transmitSize, bytes.count - offset)
                let last = offset + length == bytes.count
                var command = Data([last ? 0x80 : 0x90, 0x20,
                                    UInt8(bytes.count >> 8), UInt8(bytes.count & 0xff), UInt8(length)])
                command.append(contentsOf: bytes[offset..<(offset + length)])
                command.append(UInt8(receiveSize))
                response = try await send(command)
                if last {
                    try checkFinalStatus(response)
                } else {
                    guard response.statusWord == 0x9000 else { throw NTLExchangeError.rejected(response.statusWord) }
                    guard response.data.isEmpty else { throw NTLExchangeError.unexpectedIntermediateData }
                }
                offset += length
            }
            var result = response.data
            var blocks = 1
            while response.sw1 == 0x61 {
                // Bound zero-length or malicious continuation loops independently of byte count.
                guard blocks < 32 else { throw NTLExchangeError.tooManyResponseBlocks }
                let length = response.sw2 == 0 ? receiveSize : min(Int(response.sw2), receiveSize)
                response = try await send(Data([0, 0xc0, 0, 0, UInt8(length)]), maximumResponse: length)
                try checkFinalStatus(response)
                guard result.count + response.data.count <= Self.maximumMessageSize else {
                    throw NTLExchangeError.responseTooLarge
                }
                result.append(response.data)
                blocks += 1
            }
            // An empty successful APDU is an acknowledgement, not a Matter response packet.
            guard !result.isEmpty else { throw NTLExchangeError.invalidMessageLength }
            return result
        } catch {
            invalidate()
            throw error
        }
    }

    private func send(_ command: Data, maximumResponse: Int? = nil) async throws -> APDUResponse {
        try Task.checkCancellation()
        guard !closed else { throw NTLExchangeError.closed }
        let response = try await channel.transceive(command)
        try Task.checkCancellation()
        guard !closed else { throw NTLExchangeError.closed }
        guard response.data.count <= (maximumResponse ?? receiveSize) else {
            throw NTLExchangeError.responseTooLarge
        }
        return response
    }

    private func checkFinalStatus(_ response: APDUResponse) throws {
        guard response.statusWord == 0x9000 || response.sw1 == 0x61 else {
            throw NTLExchangeError.rejected(response.statusWord)
        }
    }
}
