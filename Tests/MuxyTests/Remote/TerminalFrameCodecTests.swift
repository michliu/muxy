import Foundation
import MuxyShared
import Testing

@Suite("TerminalFrameCodec")
struct TerminalFrameCodecTests {
    @Test("output frame round-trips")
    func outputRoundTrip() throws {
        let paneID = UUID()
        let frame = TerminalFrame.output(paneID: paneID, offset: 123_456, bytes: Data("hello world".utf8))
        let decoded = try TerminalFrameCodec.decode(TerminalFrameCodec.encode(frame))
        #expect(decoded.paneID == paneID)
        #expect(decoded.kind == .output)
        #expect(decoded.sequence == 123_456)
        #expect(decoded.payload == Data("hello world".utf8))
    }

    @Test("input frame round-trips")
    func inputRoundTrip() throws {
        let paneID = UUID()
        let frame = TerminalFrame.input(paneID: paneID, bytes: Data([0x1B, 0x5B, 0x41]))
        let decoded = try TerminalFrameCodec.decode(TerminalFrameCodec.encode(frame))
        #expect(decoded.kind == .input)
        #expect(decoded.payload == Data([0x1B, 0x5B, 0x41]))
    }

    @Test("resize frame packs and unpacks cols and rows")
    func resizeRoundTrip() throws {
        let paneID = UUID()
        let frame = TerminalFrame.resize(paneID: paneID, cols: 200, rows: 50)
        let decoded = try TerminalFrameCodec.decode(TerminalFrameCodec.encode(frame))
        #expect(decoded.kind == .resize)
        #expect(decoded.cols == 200)
        #expect(decoded.rows == 50)
        #expect(decoded.payload.isEmpty)
    }

    @Test("ack frame round-trips with empty payload")
    func ackRoundTrip() throws {
        let frame = TerminalFrame.ack(paneID: UUID(), offset: 9_999)
        let decoded = try TerminalFrameCodec.decode(TerminalFrameCodec.encode(frame))
        #expect(decoded.kind == .ack)
        #expect(decoded.sequence == 9_999)
        #expect(decoded.payload.isEmpty)
    }

    @Test("encoded header size is constant")
    func headerSize() {
        let encoded = TerminalFrameCodec.encode(.output(paneID: UUID(), offset: 0, bytes: Data([1, 2, 3])))
        #expect(encoded.count == TerminalFrameCodec.headerSize + 3)
    }

    @Test("decode rejects truncated buffer")
    func rejectsTruncated() {
        let encoded = TerminalFrameCodec.encode(.input(paneID: UUID(), bytes: Data("abc".utf8)))
        let truncated = encoded.prefix(encoded.count - 1)
        #expect(throws: TerminalFrameCodec.DecodeError.self) {
            try TerminalFrameCodec.decode(Data(truncated))
        }
    }

    @Test("decode rejects a payload-length that exceeds the buffer")
    func rejectsShortPayload() {
        var encoded = [UInt8](TerminalFrameCodec.encode(.input(paneID: UUID(), bytes: Data())))
        encoded[26] = 8
        #expect(throws: TerminalFrameCodec.DecodeError.self) {
            try TerminalFrameCodec.decode(Data(encoded))
        }
    }

    @Test("decode rejects bad version")
    func rejectsBadVersion() {
        var encoded = [UInt8](TerminalFrameCodec.encode(.input(paneID: UUID(), bytes: Data())))
        encoded[0] = 9
        #expect(throws: TerminalFrameCodec.DecodeError.self) {
            try TerminalFrameCodec.decode(Data(encoded))
        }
    }

    @Test("decode rejects unknown kind")
    func rejectsUnknownKind() {
        var encoded = [UInt8](TerminalFrameCodec.encode(.input(paneID: UUID(), bytes: Data())))
        encoded[1] = 99
        #expect(throws: TerminalFrameCodec.DecodeError.self) {
            try TerminalFrameCodec.decode(Data(encoded))
        }
    }
}
