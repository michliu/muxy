import Foundation

public struct WebTerminalConfig: Sendable, Encodable, Equatable {
    public let wsPort: UInt16
    public let serviceLabel: String

    public init(wsPort: UInt16, serviceLabel: String) {
        self.wsPort = wsPort
        self.serviceLabel = serviceLabel
    }
}
