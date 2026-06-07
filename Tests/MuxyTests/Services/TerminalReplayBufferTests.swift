import Foundation
import Testing

@testable import Muxy

@Suite("TerminalReplayBuffer")
@MainActor
struct TerminalReplayBufferTests {
    @Test("returns everything appended within capacity")
    func deltaFromStart() {
        let buffer = TerminalReplayBuffer()
        buffer.append(Data("hello".utf8))
        #expect(buffer.totalAppended == 5)
        guard case let .delta(data) = buffer.bytes(from: 0) else {
            Issue.record("expected delta")
            return
        }
        #expect(data == Data("hello".utf8))
    }

    @Test("delta from an offset returns only the bytes after it")
    func deltaFromOffset() {
        let buffer = TerminalReplayBuffer()
        buffer.append(Data("abc".utf8))
        buffer.append(Data("defg".utf8))
        guard case let .delta(data) = buffer.bytes(from: 3) else {
            Issue.record("expected delta")
            return
        }
        #expect(data == Data("defg".utf8))
    }

    @Test("offset at the head returns an empty delta")
    func deltaAtHead() {
        let buffer = TerminalReplayBuffer()
        buffer.append(Data("abc".utf8))
        guard case let .delta(data) = buffer.bytes(from: 3) else {
            Issue.record("expected delta")
            return
        }
        #expect(data.isEmpty)
    }

    @Test("offset beyond the head is treated as too old")
    func offsetBeyondHead() {
        let buffer = TerminalReplayBuffer()
        buffer.append(Data("abc".utf8))
        guard case let .tooOld(current) = buffer.bytes(from: 10) else {
            Issue.record("expected tooOld")
            return
        }
        #expect(current == 3)
    }

    @Test("eviction advances the window and reports too old for evicted offsets")
    func evictionAdvancesWindow() {
        let buffer = TerminalReplayBuffer()
        let chunk = Data(repeating: 0x41, count: TerminalReplayBuffer.capacityBytes)
        buffer.append(chunk)
        buffer.append(Data("XYZ".utf8))

        #expect(buffer.totalAppended == UInt64(TerminalReplayBuffer.capacityBytes + 3))
        #expect(buffer.windowStartOffset == 3)

        guard case .tooOld = buffer.bytes(from: 0) else {
            Issue.record("expected tooOld for evicted offset")
            return
        }
    }

    @Test("delta is exact across an eviction boundary")
    func exactDeltaAcrossEviction() {
        let buffer = TerminalReplayBuffer()
        buffer.append(Data(repeating: 0x41, count: TerminalReplayBuffer.capacityBytes - 2))
        buffer.append(Data("BCDE".utf8))

        let windowStart = buffer.windowStartOffset
        guard case let .delta(data) = buffer.bytes(from: buffer.totalAppended - 4) else {
            Issue.record("expected delta")
            return
        }
        #expect(data == Data("BCDE".utf8))
        #expect(windowStart == 2)
    }

    @Test("appending more than capacity keeps only the tail")
    func oversizedAppendKeepsTail() {
        let buffer = TerminalReplayBuffer()
        var bytes = Data(repeating: 0x2E, count: TerminalReplayBuffer.capacityBytes)
        bytes.append(Data("TAIL".utf8))
        buffer.append(bytes)

        #expect(buffer.totalAppended == UInt64(TerminalReplayBuffer.capacityBytes + 4))
        guard case let .delta(data) = buffer.bytes(from: buffer.totalAppended - 4) else {
            Issue.record("expected delta")
            return
        }
        #expect(data == Data("TAIL".utf8))
    }
}
