import Foundation

public struct HTTPStaticResponse: Sendable, Equatable {
    public let status: Int
    public let reason: String
    public let contentType: String?
    public let body: Data

    public init(status: Int, reason: String, contentType: String?, body: Data) {
        self.status = status
        self.reason = reason
        self.contentType = contentType
        self.body = body
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
