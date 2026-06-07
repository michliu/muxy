import Foundation

public enum TerminalFrameKind: UInt8, Sendable {
    case output = 1
    case input = 2
    case resize = 3
    case ack = 4
}

public struct TerminalFrame: Sendable, Equatable {
    public let paneID: UUID
    public let kind: TerminalFrameKind
    public let sequence: UInt64
    public let payload: Data

    public init(paneID: UUID, kind: TerminalFrameKind, sequence: UInt64, payload: Data) {
        self.paneID = paneID
        self.kind = kind
        self.sequence = sequence
        self.payload = payload
    }

    public static func output(paneID: UUID, offset: UInt64, bytes: Data) -> TerminalFrame {
        TerminalFrame(paneID: paneID, kind: .output, sequence: offset, payload: bytes)
    }

    public static func input(paneID: UUID, bytes: Data) -> TerminalFrame {
        TerminalFrame(paneID: paneID, kind: .input, sequence: 0, payload: bytes)
    }

    public static func resize(paneID: UUID, cols: UInt32, rows: UInt32) -> TerminalFrame {
        let packed = (UInt64(cols) << 32) | UInt64(rows)
        return TerminalFrame(paneID: paneID, kind: .resize, sequence: packed, payload: Data())
    }

    public static func ack(paneID: UUID, offset: UInt64) -> TerminalFrame {
        TerminalFrame(paneID: paneID, kind: .ack, sequence: offset, payload: Data())
    }

    public var cols: UInt32 {
        UInt32(truncatingIfNeeded: sequence >> 32)
    }

    public var rows: UInt32 {
        UInt32(truncatingIfNeeded: sequence)
    }
}

public enum TerminalFrameCodec {
    public static let version: UInt8 = 1
    public static let headerSize = 30

    public enum DecodeError: Error, Equatable {
        case truncated
        case badVersion(UInt8)
        case unknownKind(UInt8)
    }

    public static func encode(_ frame: TerminalFrame) -> Data {
        var data = Data(capacity: headerSize + frame.payload.count)
        data.append(version)
        data.append(frame.kind.rawValue)
        withUnsafeBytes(of: frame.paneID.uuid) { data.append(contentsOf: $0) }
        appendLittleEndian(&data, frame.sequence)
        appendLittleEndian(&data, UInt32(frame.payload.count))
        data.append(frame.payload)
        return data
    }

    public static func decode(_ data: Data) throws -> TerminalFrame {
        guard data.count >= headerSize else { throw DecodeError.truncated }
        let bytes = [UInt8](data)

        let frameVersion = bytes[0]
        guard frameVersion == version else { throw DecodeError.badVersion(frameVersion) }

        guard let kind = TerminalFrameKind(rawValue: bytes[1]) else {
            throw DecodeError.unknownKind(bytes[1])
        }

        let uuid = uuidT(from: bytes, at: 2)
        let sequence = readLittleEndianUInt64(bytes, at: 18)
        let payloadLength = Int(readLittleEndianUInt32(bytes, at: 26))

        guard bytes.count >= headerSize + payloadLength else { throw DecodeError.truncated }
        let payload = Data(bytes[headerSize ..< headerSize + payloadLength])

        return TerminalFrame(paneID: UUID(uuid: uuid), kind: kind, sequence: sequence, payload: payload)
    }

    private static func appendLittleEndian(_ data: inout Data, _ value: UInt64) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func appendLittleEndian(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func readLittleEndianUInt64(_ bytes: [UInt8], at index: Int) -> UInt64 {
        var value: UInt64 = 0
        for offset in 0 ..< 8 {
            value |= UInt64(bytes[index + offset]) << (8 * offset)
        }
        return value
    }

    private static func readLittleEndianUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        var value: UInt32 = 0
        for offset in 0 ..< 4 {
            value |= UInt32(bytes[index + offset]) << (8 * offset)
        }
        return value
    }

    private static func uuidT(from bytes: [UInt8], at index: Int) -> uuid_t {
        (
            bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3],
            bytes[index + 4], bytes[index + 5], bytes[index + 6], bytes[index + 7],
            bytes[index + 8], bytes[index + 9], bytes[index + 10], bytes[index + 11],
            bytes[index + 12], bytes[index + 13], bytes[index + 14], bytes[index + 15]
        )
    }
}
