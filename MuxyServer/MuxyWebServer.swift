import Foundation
import Network
import os

private let logger = Logger(subsystem: "app.muxy", category: "WebServer")

public final class MuxyWebServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 4864

    private let port: UInt16
    private let resourceRoot: URL
    private let config: WebTerminalConfig
    private let queue = DispatchQueue(label: "app.muxy.webServer")
    private var listener: NWListener?
    private var startCompletion: (@Sendable (Result<Void, Error>) -> Void)?

    public init(port: UInt16, resourceRoot: URL, config: WebTerminalConfig) {
        self.port = port
        self.resourceRoot = resourceRoot
        self.config = config
    }

    public func start(completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.startCompletion = completion
            self.startListener()
        }
    }

    public func stop(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            completion?()
        }
    }

    private func startListener() {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            finishStart(.failure(NWError.posix(.EINVAL)))
            return
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: endpointPort)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.finishStart(.success(()))
                case let .failed(error):
                    logger.error("Web server listener failed: \(error.localizedDescription)")
                    self?.finishStart(.failure(error))
                    self?.listener?.cancel()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            logger.error("Web server failed to create listener: \(error.localizedDescription)")
            finishStart(.failure(error))
        }
    }

    private func finishStart(_ result: Result<Void, Error>) {
        guard let completion = startCompletion else { return }
        startCompletion = nil
        completion(result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(connection, request: buffer)
                return
            }
            if isComplete || error != nil || buffer.count >= 8192 {
                self.respond(connection, request: buffer)
                return
            }
            self.receive(connection, accumulated: buffer)
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        let response = HTTPStaticResponder.response(
            rawRequest: request,
            resourceRoot: resourceRoot,
            config: config
        )
        connection.send(content: response.serialized(), isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
