import Foundation
import Testing
@testable import MuxyServer

struct HTTPStaticResponderTests {
    @Test func serializesStatusLineAndHeaders() {
        let response = HTTPStaticResponse(
            status: 200,
            reason: "OK",
            contentType: "text/plain",
            body: Data("hi".utf8)
        )
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: text/plain\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\nhi"))
    }

    @Test func omitsContentTypeWhenNil() {
        let response = HTTPStaticResponse(status: 404, reason: "Not Found", contentType: nil, body: Data())
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(!text.contains("Content-Type:"))
        #expect(text.contains("Content-Length: 0\r\n"))
    }
}
