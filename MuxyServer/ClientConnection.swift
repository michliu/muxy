import Foundation
import MuxyShared
import Network
import os

private let logger = Logger(subsystem: "app.muxy", category: "ClientConnection")

final class ClientConnection: @unchecked Sendable {
    let id: UUID
    private let connection: NWConnection
    private weak var server: MuxyRemoteServer?

    init(id: UUID, connection: NWConnection, server: MuxyRemoteServer) {
        self.id = id
        self.connection = connection
        self.server = server
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveNextMessage()
            case .failed,
                 .cancelled:
                self.server?.removeConnection(self.id)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    func send(_ data: Data) {
        send(data, opcode: .text)
    }

    func sendBinary(_ data: Data) {
        send(data, opcode: .binary)
    }

    private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(
            identifier: "muxy",
            metadata: [metadata]
        )
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    logger.error("Send error: \(error)")
                }
            }
        )
    }

    private func receiveNextMessage() {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }

            if let error {
                logger.error("Receive error: \(error)")
                self.server?.removeConnection(self.id)
                return
            }

            guard let content, !content.isEmpty else {
                self.receiveNextMessage()
                return
            }

            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            guard let metadata, metadata.opcode == .text || metadata.opcode == .binary else {
                self.receiveNextMessage()
                return
            }

            self.handleData(content, isBinary: metadata.opcode == .binary)
            self.receiveNextMessage()
        }
    }

    private func handleData(_ data: Data, isBinary: Bool) {
        if isBinary {
            handleBinary(data)
            return
        }
        do {
            let message = try MuxyCodec.decode(data)
            switch message {
            case let .request(request):
                server?.handleRequest(request, from: id)
            case .response,
                 .event:
                break
            }
        } catch {
            logger.error("Failed to decode message: \(error)")
        }
    }

    private func handleBinary(_ data: Data) {
        do {
            let frame = try TerminalFrameCodec.decode(data)
            server?.handleTerminalFrame(frame, from: id)
        } catch {
            logger.error("Failed to decode terminal frame: \(error)")
        }
    }
}
