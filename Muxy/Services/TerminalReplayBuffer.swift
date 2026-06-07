import Foundation

@MainActor
final class TerminalReplayBuffer {
    enum ReplaySlice {
        case delta(Data)
        case tooOld(currentOffset: UInt64)
    }

    static let capacityBytes = 256 * 1024

    private var storage: [UInt8]
    private var start = 0
    private var count = 0
    private(set) var totalAppended: UInt64 = 0

    init() {
        storage = [UInt8](repeating: 0, count: Self.capacityBytes)
    }

    var windowStartOffset: UInt64 {
        totalAppended - UInt64(count)
    }

    func append(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        totalAppended += UInt64(bytes.count)

        if bytes.count >= Self.capacityBytes {
            let tail = bytes.suffix(Self.capacityBytes)
            for (index, byte) in tail.enumerated() {
                storage[index] = byte
            }
            start = 0
            count = Self.capacityBytes
            return
        }

        for byte in bytes {
            let writeIndex = (start + count) % Self.capacityBytes
            storage[writeIndex] = byte
            if count < Self.capacityBytes {
                count += 1
            } else {
                start = (start + 1) % Self.capacityBytes
            }
        }
    }

    func bytes(from offset: UInt64) -> ReplaySlice {
        if offset > totalAppended {
            return .tooOld(currentOffset: totalAppended)
        }
        if offset < windowStartOffset {
            return .tooOld(currentOffset: totalAppended)
        }

        let available = Int(totalAppended - offset)
        guard available > 0 else { return .delta(Data()) }

        var result = [UInt8]()
        result.reserveCapacity(available)
        let begin = count - available
        for index in begin ..< count {
            result.append(storage[(start + index) % Self.capacityBytes])
        }
        return .delta(Data(result))
    }
}
