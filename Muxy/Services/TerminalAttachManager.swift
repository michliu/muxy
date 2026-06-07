import Foundation
import MuxyShared

@MainActor
@Observable
final class TerminalAttachManager {
    static let shared = TerminalAttachManager()

    private var clientsByPane: [UUID: Set<UUID>] = [:]
    private var panesByClient: [UUID: Set<UUID>] = [:]
    private var buffers: [UUID: TerminalReplayBuffer] = [:]
    private var deviceNames: [UUID: String] = [:]

    var onAttachmentChanged: ((UUID) -> Void)?

    private init() {}

    func registerDevice(clientID: UUID, name: String) {
        deviceNames[clientID] = name
    }

    func deviceName(for clientID: UUID) -> String? {
        deviceNames[clientID]
    }

    func attach(paneID: UUID, clientID: UUID) {
        if buffers[paneID] == nil {
            buffers[paneID] = TerminalReplayBuffer()
        }
        clientsByPane[paneID, default: []].insert(clientID)
        panesByClient[clientID, default: []].insert(paneID)
        onAttachmentChanged?(paneID)
    }

    func detach(paneID: UUID, clientID: UUID) {
        removeAttachment(paneID: paneID, clientID: clientID)
    }

    func detachAll(clientID: UUID) {
        guard let panes = panesByClient.removeValue(forKey: clientID) else {
            deviceNames.removeValue(forKey: clientID)
            return
        }
        for paneID in panes {
            clientsByPane[paneID]?.remove(clientID)
            if clientsByPane[paneID]?.isEmpty == true {
                clientsByPane.removeValue(forKey: paneID)
                buffers.removeValue(forKey: paneID)
            }
            onAttachmentChanged?(paneID)
        }
        deviceNames.removeValue(forKey: clientID)
    }

    func isAttached(clientID: UUID, paneID: UUID) -> Bool {
        clientsByPane[paneID]?.contains(clientID) ?? false
    }

    func hasAnyAttachment(paneID: UUID) -> Bool {
        !(clientsByPane[paneID]?.isEmpty ?? true)
    }

    func attachedClients(for paneID: UUID) -> Set<UUID> {
        clientsByPane[paneID] ?? []
    }

    func buffer(for paneID: UUID) -> TerminalReplayBuffer? {
        buffers[paneID]
    }

    func appendIfBuffered(paneID: UUID, bytes: Data) -> UInt64? {
        guard let buffer = buffers[paneID] else { return nil }
        let start = buffer.totalAppended
        buffer.append(bytes)
        return start
    }

    private func removeAttachment(paneID: UUID, clientID: UUID) {
        clientsByPane[paneID]?.remove(clientID)
        panesByClient[clientID]?.remove(paneID)
        if panesByClient[clientID]?.isEmpty == true {
            panesByClient.removeValue(forKey: clientID)
        }
        if clientsByPane[paneID]?.isEmpty == true {
            clientsByPane.removeValue(forKey: paneID)
            buffers.removeValue(forKey: paneID)
        }
        onAttachmentChanged?(paneID)
    }
}
