import XCTest
@testable import NFCProbeCore

@MainActor
private final class ScriptedChannel: APDUChannel {
    var commands: [Data] = []
    var invalidated = false
    var replies: [APDUResponse]
    var failure: Error?
    var suspended: CheckedContinuation<APDUResponse, Error>?
    var hold = false

    init(_ replies: [APDUResponse] = []) { self.replies = replies }
    func transceive(_ command: Data) async throws -> APDUResponse {
        commands.append(command)
        if let failure { throw failure }
        if hold {
            return try await withCheckedThrowingContinuation { suspended = $0 }
        }
        guard !replies.isEmpty else { throw NTLExchangeError.communicationFailed }
        return replies.removeFirst()
    }
    func invalidate() {
        invalidated = true
        suspended?.resume(throwing: NTLExchangeError.closed)
        suspended = nil
    }
}

@MainActor
final class NTLExchangeTests: XCTestCase {
    private func reply(_ bytes: [UInt8] = [], _ sw1: UInt8 = 0x90, _ sw2: UInt8 = 0) -> APDUResponse {
        APDUResponse(data: Data(bytes), sw1: sw1, sw2: sw2)
    }

    func testSingleMessageUsesTransportHeaderAndReturnsPayloadWithoutStatus() async throws {
        let channel = ScriptedChannel([reply([0xaa, 0xbb])])
        let exchange = try NTLExchange(channel: channel)
        let result = try await exchange.exchange(Data([1, 2, 3]))
        XCTAssertEqual(result, Data([0xaa, 0xbb]))
        XCTAssertEqual(channel.commands, [Data([0x80, 0x20, 0, 3, 3, 1, 2, 3, 254])])
    }

    func testTransmitBoundaryAndTotalLengthOnEveryBlock() async throws {
        let channel = ScriptedChannel([reply(), reply([7])])
        let exchange = try NTLExchange(channel: channel)
        _ = try await exchange.exchange(Data(repeating: 0xab, count: 251))
        XCTAssertEqual(channel.commands.count, 2)
        XCTAssertEqual(channel.commands[0].count, 256)
        XCTAssertEqual(Array(channel.commands[0].prefix(5)), [0x90, 0x20, 0, 251, 250])
        XCTAssertEqual(channel.commands[1], Data([0x80, 0x20, 0, 251, 1, 0xab, 254]))
    }

    func testMaximumMessageUsesBigEndianLength() async throws {
        let channel = ScriptedChannel(Array(repeating: reply(), count: 5) + [reply([1])])
        _ = try await NTLExchange(channel: channel).exchange(Data(repeating: 1, count: 1280))
        XCTAssertEqual(channel.commands.count, 6)
        for command in channel.commands { XCTAssertEqual(Array(command[2...3]), [5, 0]) }
        XCTAssertEqual(channel.commands.last?[4], 30)
    }

    func testChainedResponseUsesGetResponseAndClampsZeroLength() async throws {
        let channel = ScriptedChannel([reply([1], 0x61, 2), reply([2, 3], 0x61, 0), reply([4])])
        let result = try await NTLExchange(channel: channel).exchange(Data([1]))
        XCTAssertEqual(result, Data([1, 2, 3, 4]))
        XCTAssertEqual(Array(channel.commands.suffix(2)), [Data([0, 0xc0, 0, 0, 2]), Data([0, 0xc0, 0, 0, 254])])
    }

    func testRejectsInvalidLengthsWithoutSending() async throws {
        let channel = ScriptedChannel()
        let exchange = try NTLExchange(channel: channel)
        for length in [0, 1281] {
            do {
                _ = try await exchange.exchange(Data(repeating: 0, count: length))
                XCTFail("Invalid message accepted")
            } catch { XCTAssertEqual(error as? NTLExchangeError, .invalidMessageLength) }
        }
        XCTAssertTrue(channel.commands.isEmpty)
    }

    func testIntermediateFailureAbortsRemainingFragments() async throws {
        let channel = ScriptedChannel([reply([], 0x6a, 0x80)])
        do {
            _ = try await NTLExchange(channel: channel).exchange(Data(repeating: 0, count: 251))
            XCTFail("Rejected fragment accepted")
        } catch { XCTAssertEqual(error as? NTLExchangeError, .rejected(0x6a80)) }
        XCTAssertEqual(channel.commands.count, 1)
        XCTAssertTrue(channel.invalidated)
    }

    func testRejectsDataInIntermediateAckAndEmptyFinalResponse() async throws {
        for length in [251, 1] {
            let channel = ScriptedChannel([reply(length == 251 ? [1] : [])])
            do {
                _ = try await NTLExchange(channel: channel).exchange(Data(repeating: 0, count: length))
                XCTFail("Malformed response accepted")
            } catch {
                XCTAssertEqual(error as? NTLExchangeError, length == 251 ? .unexpectedIntermediateData : .invalidMessageLength)
            }
            XCTAssertTrue(channel.invalidated)
        }
    }

    func testResponseExceedingRequestedLengthFails() async throws {
        let channel = ScriptedChannel([reply([], 0x61, 1), reply([1, 2])])
        do {
            _ = try await NTLExchange(channel: channel).exchange(Data([1]))
            XCTFail("Oversized response accepted")
        } catch { XCTAssertEqual(error as? NTLExchangeError, .responseTooLarge) }
    }

    func testTotalResponseBoundAndEndlessContinuationBound() async throws {
        for size in [254, 0] {
            let channel = ScriptedChannel(Array(repeating: reply(Array(repeating: 0, count: size), 0x61, 0), count: 33))
            do {
                _ = try await NTLExchange(channel: channel).exchange(Data([1]))
                XCTFail("Unbounded response accepted")
            } catch {
                XCTAssertEqual(error as? NTLExchangeError, size == 0 ? .tooManyResponseBlocks : .responseTooLarge)
            }
            XCTAssertLessThanOrEqual(channel.commands.count, 32)
        }
    }

    func testTimeoutClosesExchangeAndDisallowsReuse() async throws {
        let channel = ScriptedChannel()
        channel.failure = NTLExchangeError.timedOut
        let exchange = try NTLExchange(channel: channel)
        do { _ = try await exchange.exchange(Data([1])); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? NTLExchangeError, .timedOut) }
        do { _ = try await exchange.exchange(Data([1])); XCTFail("Closed exchange reused") }
        catch { XCTAssertEqual(error as? NTLExchangeError, .closed) }
        XCTAssertEqual(channel.commands.count, 1)
    }

    func testConcurrentMessageRejectedAndInvalidationUnblocksPendingExchange() async throws {
        let channel = ScriptedChannel()
        channel.hold = true
        let exchange = try NTLExchange(channel: channel)
        let first = Task { try await exchange.exchange(Data([1])) }
        while channel.suspended == nil { await Task.yield() }
        do { _ = try await exchange.exchange(Data([2])); XCTFail("Concurrent message accepted") }
        catch { XCTAssertEqual(error as? NTLExchangeError, .busy) }
        exchange.invalidate()
        do { _ = try await first.value; XCTFail("Invalidation ignored") }
        catch { XCTAssertEqual(error as? NTLExchangeError, .closed) }
        XCTAssertEqual(channel.commands.count, 1)
    }

    func testCancellationBeforeSendDoesNotTransmit() async throws {
        let channel = ScriptedChannel([reply([1])])
        let exchange = try NTLExchange(channel: channel)
        let task = Task { try await exchange.exchange(Data([1])) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(channel.commands.isEmpty)
        XCTAssertTrue(channel.invalidated)
    }

    func testReaderFailurePreservesCodeAndDoesNotRetryCommand() async throws {
        let channel = ScriptedChannel()
        channel.failure = NTLExchangeError.readerError(100)
        let exchange = try NTLExchange(channel: channel)
        do { _ = try await exchange.exchange(Data([1])); XCTFail("Expected reader failure") }
        catch { XCTAssertEqual(error as? NTLExchangeError, .readerError(100)) }
        XCTAssertTrue(channel.invalidated)
        do { _ = try await exchange.exchange(Data([1])); XCTFail("Closed exchange reused") }
        catch { XCTAssertEqual(error as? NTLExchangeError, .closed) }
        XCTAssertEqual(channel.commands.count, 1)
    }
}
